//! Launches the installed Erlang release as a child process and mirrors its exit code.

use std::ffi::OsString;
use std::fs;
use std::io;
use std::path::Path;
use std::process::{Command, ExitStatus};

use crate::logger::debug;
use crate::metadata::Metadata;

#[cfg(windows)]
const ERL_EXE_NAME: &str = "erl.exe";
#[cfg(not(windows))]
const ERL_EXE_NAME: &str = "erlexec";

pub fn launch(
    install_dir: &Path,
    meta: &Metadata,
    self_path: &Path,
    args: &[OsString],
    is_tty: bool,
) -> io::Result<i32> {
    let rel_vsn_dir = install_dir.join("releases").join(&meta.app_version);
    let release_cookie_path = install_dir.join("releases").join("COOKIE");
    let release_lib_path = install_dir.join("lib");
    let vm_args_path = rel_vsn_dir.join("vm.args");
    let sys_config_path = rel_vsn_dir.join("sys.config");
    let sys_config_path_no_ext = rel_vsn_dir.join("sys");
    let boot_path = rel_vsn_dir.join("start");

    let erts_bin_path = install_dir
        .join(format!("erts-{}", meta.erts_version))
        .join("bin");
    let erl_bin_path = erts_bin_path.join(ERL_EXE_NAME);

    // Use RELEASE_COOKIE if set, otherwise the release's COOKIE file. Trailing newlines are
    // stripped, matching what the Mix release start script does with `$(cat COOKIE)`.
    let cookie = match std::env::var_os("RELEASE_COOKIE") {
        Some(cookie) => cookie,
        None => {
            let content = fs::read_to_string(&release_cookie_path).map_err(|e| {
                io::Error::new(
                    e.kind(),
                    format!("failed to read {}: {e}", release_cookie_path.display()),
                )
            })?;
            OsString::from(content.trim_end_matches(['\r', '\n']))
        }
    };

    // CLI args are passed through after `-extra` and reach the BEAM via
    // :init.get_plain_arguments/0.
    let mut command = Command::new(&erl_bin_path);
    // NOTE: "-mode embedded" is intentionally a single argv entry, exactly as the
    // previous (Zig) wrapper passed it, to keep runtime behavior unchanged.
    #[allow(clippy::suspicious_command_arg_space)]
    command
        .args(["-elixir", "ansi_enabled", "true"])
        .args(["-noshell", "-s", "elixir", "start_cli"])
        .arg("-mode embedded")
        .arg("-setcookie")
        .arg(&cookie)
        .arg("-boot")
        .arg(&boot_path)
        .args(["-boot_var", "RELEASE_LIB"])
        .arg(&release_lib_path)
        .arg("-args_file")
        .arg(&vm_args_path)
        .arg("-config")
        .arg(&sys_config_path)
        .arg("-extra")
        .args(args);

    command
        .env("_IS_TTY", if is_tty { "1" } else { "0" })
        .env("RELEASE_ROOT", install_dir)
        .env("RELEASE_SYS_CONFIG", &sys_config_path_no_ext)
        .env("__BURRITO_NG", "1")
        .env("__BURRITO_NG_BIN_PATH", self_path);

    #[cfg(unix)]
    {
        command
            .env("ROOTDIR", install_dir)
            .env("BINDIR", &erts_bin_path);

        // Extend LD_LIBRARY_PATH so NIF .so files can find system shared
        // libraries (e.g. libgcc_s.so.1) when using a custom ERTS.
        let arch = std::env::consts::ARCH;
        let system_lib_paths =
            format!("/lib/{arch}-linux-gnu:/usr/lib/{arch}-linux-gnu:/lib:/usr/lib");
        let ld_library_path = match std::env::var_os("LD_LIBRARY_PATH") {
            Some(existing) if !existing.is_empty() => {
                let mut combined = existing;
                combined.push(":");
                combined.push(&system_lib_paths);
                combined
            }
            _ => OsString::from(system_lib_paths),
        };
        command.env("LD_LIBRARY_PATH", ld_library_path);
    }

    debug!("Launching erlang: {command:?}");

    let status = run(command)?;
    Ok(status.code().unwrap_or(1))
}

/// On Unix the child's stdout is piped through us so we can detect a broken pipe from
/// the downstream consumer (e.g. `app cmd | head -5`). When that happens the child is
/// killed, otherwise the BEAM hangs during shutdown trying to flush standard_io into
/// a dead pipe.
#[cfg(unix)]
fn run(mut command: Command) -> io::Result<ExitStatus> {
    use std::io::{Read, Write};
    use std::process::Stdio;

    let mut child = command.stdout(Stdio::piped()).spawn()?;
    let mut child_stdout = child.stdout.take().expect("child stdout is piped");
    let pid = child.id() as libc::pid_t;

    let copier = std::thread::spawn(move || {
        let mut stdout = io::stdout().lock();
        let mut buf = [0u8; 16 * 1024];
        loop {
            let n = match child_stdout.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => n,
                Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(_) => break,
            };
            if stdout
                .write_all(&buf[..n])
                .and_then(|_| stdout.flush())
                .is_err()
            {
                // SAFETY: plain syscall; `pid` belongs to our not-yet-reaped child
                // (the main thread is blocked in `wait` until it exits).
                unsafe {
                    libc::kill(pid, libc::SIGKILL);
                }
                break;
            }
        }
    });

    let status = child.wait();
    let _ = copier.join();
    status
}

/// On Windows the child inherits our stdout directly.
#[cfg(not(unix))]
fn run(mut command: Command) -> io::Result<ExitStatus> {
    command.status()
}
