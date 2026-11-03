// A Burrito NG plugin is a plain Rust source file that is compiled into the wrapper.
// It must define `burrito_ng_plugin_entry`, which runs before the payload is installed.
// Plugins can only use the Rust standard library.

pub fn burrito_ng_plugin_entry(install_dir: &str, program_manifest_json: &str) {
    eprintln!("Test Plugin Init!");
    eprintln!("Test Plugin: {install_dir}");
    eprintln!("Test Plugin: {program_manifest_json}");
}
