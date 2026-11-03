//! The payload embedded in the wrapper: the Mix release directory as an
//! xz-compressed tar archive.
//!
//! Archiving is done by the `tar` crate, compression by `lzma-rust2`. This module only
//! configures them, and is shared between the build script (packing, on the build host)
//! and the wrapper (unpacking, on the target machine).

use std::io::{self, Read, Write};
use std::path::Path;

/// Packs `release_dir` into `out` as a tar archive compressed with the given xz preset (0-9).
pub fn pack<W: Write>(release_dir: &Path, out: W, preset: u32) -> io::Result<W> {
    let mut options = lzma_rust2::XzOptions::with_preset(preset);
    options.set_check_sum_type(lzma_rust2::CheckType::Crc32);
    let xz = lzma_rust2::XzWriter::new(out, options)?;

    let mut tar = tar::Builder::new(io::BufWriter::with_capacity(1 << 20, xz));
    // Reproducible archives: no timestamps/owners, modes normalized to 0o644 / 0o755
    // (the executable bit is kept, so erlexec, beam.smp, etc. stay runnable).
    tar.mode(tar::HeaderMode::Deterministic);
    tar.append_dir_all(".", release_dir)?;

    let xz = tar.into_inner()?.into_inner().map_err(|e| e.into_error())?;
    xz.finish()
}

/// Decompresses and unpacks a payload produced by [`pack`] into `dest`.
pub fn unpack<R: Read>(compressed: R, dest: &Path) -> io::Result<()> {
    let xz = lzma_rust2::XzReader::new(compressed, false);
    let mut archive = tar::Archive::new(io::BufReader::with_capacity(1 << 16, xz));
    archive.set_preserve_permissions(true);
    archive.set_preserve_mtime(false);
    archive.set_overwrite(true);
    archive.unpack(dest)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;

    fn temp_dir(tag: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("burrito_ng_payload_{tag}_{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn round_trip() {
        let src = temp_dir("src");
        fs::create_dir_all(src.join("lib/app-0.1.0/ebin")).unwrap();
        fs::create_dir_all(src.join("empty_dir")).unwrap();
        fs::write(src.join("lib/app-0.1.0/ebin/app.beam"), b"beam bytes").unwrap();
        fs::write(src.join("empty_file"), b"").unwrap();
        fs::write(src.join("erlexec"), vec![7u8; 300_000]).unwrap();
        // Longer than the 100 byte limit of plain ustar names
        let long = "a".repeat(120);
        fs::write(src.join(&long), b"long").unwrap();

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(src.join("erlexec"), fs::Permissions::from_mode(0o751)).unwrap();
        }

        let compressed = pack(&src, Vec::new(), 6).unwrap();

        let dest = temp_dir("dest");
        unpack(&compressed[..], &dest).unwrap();

        assert_eq!(
            fs::read(dest.join("lib/app-0.1.0/ebin/app.beam")).unwrap(),
            b"beam bytes"
        );
        assert_eq!(fs::read(dest.join("empty_file")).unwrap(), b"");
        assert_eq!(fs::read(dest.join("erlexec")).unwrap(), vec![7u8; 300_000]);
        assert_eq!(fs::read(dest.join(&long)).unwrap(), b"long");
        assert!(dest.join("empty_dir").is_dir());

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = |p: &str| fs::metadata(dest.join(p)).unwrap().permissions().mode() & 0o777;
            assert_eq!(mode("erlexec"), 0o755);
            assert_eq!(mode("empty_file"), 0o644);
        }

        fs::remove_dir_all(&src).unwrap();
        fs::remove_dir_all(&dest).unwrap();
    }

    #[test]
    fn rejects_garbage() {
        let dest = temp_dir("garbage");
        assert!(unpack(&b"definitely not xz"[..], &dest).is_err());
        fs::remove_dir_all(&dest).unwrap();
    }
}
