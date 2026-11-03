//! `<binary> maintenance <command>` sub-commands and cleanup of old installs.

use std::fs;
use std::io::{self, BufRead, Write};
use std::path::{Path, PathBuf};

use crate::logger::{debug, err, info, log_stderr, query, warning};
use crate::metadata::Metadata;

pub fn run(args: &[String], install_dir: &Path, metadata_json: &str) -> io::Result<()> {
    let Some(command) = args.first() else {
        warning!("No sub-command provided!");
        return Ok(());
    };

    match command.as_str() {
        "uninstall" => uninstall(install_dir),
        "directory" => {
            let mut out = io::stdout().lock();
            writeln!(out, "{}", install_dir.display())?;
            out.flush()
        }
        "meta" => {
            let mut out = io::stdout().lock();
            write!(out, "{metadata_json}")?;
            out.flush()
        }
        other => {
            warning!("Unknown maintenance sub-command: {other}");
            Ok(())
        }
    }
}

fn confirm() -> io::Result<bool> {
    query!("Please confirm this action [y/n]: ");

    let mut line = String::new();
    io::stdin().lock().read_line(&mut line).inspect_err(|e| {
        err!("Failed to confirm: {e}");
    })?;

    Ok(matches!(line.trim_start().chars().next(), Some('y' | 'Y')))
}

fn uninstall(install_dir: &Path) -> io::Result<()> {
    warning!("This will uninstall the application runtime for this Burrito NG binary!");
    if !confirm()? {
        warning!("Uninstall was aborted!");
        info!("Quitting.");
        return Ok(());
    }

    info!("Deleting directory: {}", install_dir.display());
    match fs::remove_dir_all(install_dir) {
        Ok(()) => {}
        Err(e) if e.kind() == io::ErrorKind::NotFound => {}
        Err(e) => return Err(e),
    }
    info!("Uninstall complete!");
    info!("Quitting.");
    Ok(())
}

struct Install {
    path: PathBuf,
    metadata: Metadata,
    version: semver::Version,
}

fn load_install(path: &Path) -> Option<Install> {
    let metadata_path = path.join("_metadata.json");
    let content = fs::read_to_string(&metadata_path)
        .inspect_err(|e| debug!("No metadata at {}: {e}", metadata_path.display()))
        .ok()?;

    let metadata = Metadata::parse(&content)
        .inspect_err(|e| {
            err!(
                "Failed to parse metadata file {}: {e}",
                metadata_path.display()
            )
        })
        .ok()?;

    let version = semver::Version::parse(&metadata.app_version)
        .inspect_err(|e| {
            err!(
                "Failed to parse the app version in {}: {e}",
                metadata_path.display()
            )
        })
        .ok()?;

    Some(Install {
        path: path.to_path_buf(),
        metadata,
        version,
    })
}

/// Deletes installs of this application (found in `base_install_dir`) that are older
/// than the one at `current_install_dir`.
pub fn clean_old_versions(base_install_dir: &Path, current_install_dir: &Path) -> io::Result<()> {
    debug!("Going to clean up older versions of this application...");

    let Some(current) = load_install(current_install_dir) else {
        debug!("Current install has no readable metadata, skipping cleanup");
        return Ok(());
    };

    for entry in fs::read_dir(base_install_dir)? {
        let entry = entry?;
        if !entry.file_type()?.is_dir() {
            continue;
        }

        let Some(other) = load_install(&entry.path()) else {
            continue;
        };

        if other.metadata.app_name != current.metadata.app_name {
            continue;
        }

        if current.version > other.version {
            fs::remove_dir_all(&other.path)?;
            log_stderr!(
                "Uninstalled older version (v{})",
                other.metadata.app_version
            );
        }
    }

    Ok(())
}
