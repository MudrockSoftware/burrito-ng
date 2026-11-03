use std::path::Path;

pub fn burrito_ng_plugin_entry(install_dir: &str, program_manifest_json: &str) {
    eprintln!("Rust Plugin Init!");
    eprintln!("Install Dir: {install_dir}");
    eprintln!(": {program_manifest_json}");

    if Path::new("only_one.lock").exists() {
        eprintln!("We found a lockfile! Can't run two of this application at one!");
        std::process::exit(0);
    }
}
