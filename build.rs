//! Build script for the Burrito NG wrapper.
//!
//! Inputs are passed in by `BurritoNg.Steps.Build.PackAndBuild` through environment variables:
//!
//! * `__BURRITO_NG_RELEASE_PATH`       - Mix release directory to pack into the payload.
//! * `__BURRITO_NG_RELEASE_NAME`       - Name of the release.
//! * `__BURRITO_NG_METADATA_PATH`      - JSON metadata file to embed.
//! * `__BURRITO_NG_IS_PROD`            - "1" for production builds (skips re-installs, quiets debug logs).
//! * `__BURRITO_NG_PLUGIN_PATH`        - Optional Rust source file with `burrito_ng_plugin_entry/2`.
//! * `__BURRITO_NG_MUSL_RUNTIME_FILE`  - Optional musl libc `.so` to embed (Linux targets).
//! * `__BURRITO_NG_MUSL_RUNTIME_PATH`  - Where the wrapper should extract that `.so` at runtime.
//!
//! When `__BURRITO_NG_RELEASE_PATH` is not set (e.g. plain `cargo check` / `cargo test` during
//! development) a stub payload is generated so the crate still compiles.

use std::env;
use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};

#[path = "src/payload.rs"]
#[allow(dead_code)]
mod payload;

const ENV_VARS: &[&str] = &[
    "__BURRITO_NG_RELEASE_PATH",
    "__BURRITO_NG_RELEASE_NAME",
    "__BURRITO_NG_METADATA_PATH",
    "__BURRITO_NG_IS_PROD",
    "__BURRITO_NG_PLUGIN_PATH",
    "__BURRITO_NG_MUSL_RUNTIME_FILE",
    "__BURRITO_NG_MUSL_RUNTIME_PATH",
];

const DUMMY_PLUGIN: &str = "\
pub fn burrito_ng_plugin_entry(_install_dir: &str, _program_manifest_json: &str) {}
";

fn main() {
    println!("cargo::rustc-check-cfg=cfg(burrito_ng_stub)");
    println!("cargo::rerun-if-changed=build.rs");
    println!("cargo::rerun-if-changed=src/payload.rs");
    for var in ENV_VARS {
        println!("cargo::rerun-if-env-changed={var}");
    }

    let out_dir = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR not set"));

    let release_path = non_empty_env("__BURRITO_NG_RELEASE_PATH");
    let is_stub = release_path.is_none();
    if is_stub {
        println!("cargo::rustc-cfg=burrito_ng_stub");
        println!(
            "cargo::warning=__BURRITO_NG_RELEASE_PATH is not set, building a stub wrapper without a payload"
        );
    }

    let is_prod = non_empty_env("__BURRITO_NG_IS_PROD").is_none_or(|v| v == "1");
    let release_name =
        non_empty_env("__BURRITO_NG_RELEASE_NAME").unwrap_or_else(|| "burrito_ng_stub".to_string());
    let musl_runtime_path = non_empty_env("__BURRITO_NG_MUSL_RUNTIME_PATH").unwrap_or_default();

    // Payload
    let payload_out = out_dir.join("payload.tar.xz");
    match &release_path {
        Some(path) => {
            println!("cargo::rerun-if-changed={path}");
            pack_payload(Path::new(path), &payload_out, is_prod);
        }
        None => fs::write(&payload_out, b"").unwrap(),
    }

    // Metadata
    let metadata_out = out_dir.join("_metadata.json");
    match non_empty_env("__BURRITO_NG_METADATA_PATH") {
        Some(path) => {
            println!("cargo::rerun-if-changed={path}");
            fs::copy(&path, &metadata_out)
                .unwrap_or_else(|e| panic!("failed to copy metadata file {path}: {e}"));
        }
        None if is_stub => fs::write(
            &metadata_out,
            br#"{"app_name":"burrito_ng_stub","app_version":"0.0.0","erts_version":"0.0"}"#,
        )
        .unwrap(),
        None => panic!("__BURRITO_NG_METADATA_PATH must be set when building a real payload"),
    }

    // Plugin
    let plugin_out = out_dir.join("plugin.rs");
    match non_empty_env("__BURRITO_NG_PLUGIN_PATH") {
        Some(path) => {
            println!("cargo::rerun-if-changed={path}");
            println!("cargo::warning=Using Burrito NG plugin: {path}");
            fs::copy(&path, &plugin_out)
                .unwrap_or_else(|e| panic!("failed to copy plugin file {path}: {e}"));
        }
        None => fs::write(&plugin_out, DUMMY_PLUGIN).unwrap(),
    }

    // musl runtime (only embedded into Linux wrappers)
    let musl_out = out_dir.join("musl-runtime.so");
    match non_empty_env("__BURRITO_NG_MUSL_RUNTIME_FILE") {
        Some(path) => {
            println!("cargo::rerun-if-changed={path}");
            fs::copy(&path, &musl_out)
                .unwrap_or_else(|e| panic!("failed to copy musl runtime {path}: {e}"));
        }
        None => fs::write(&musl_out, b"").unwrap(),
    }

    // Compile-time configuration for the wrapper
    let config = format!(
        "pub const RELEASE_NAME: &str = {release_name:?};\n\
         pub const IS_PROD: bool = {is_prod};\n\
         pub const MUSL_RUNTIME_PATH: &str = {musl_runtime_path:?};\n"
    );
    fs::write(out_dir.join("config.rs"), config).unwrap();
}

fn pack_payload(release_path: &Path, payload_out: &Path, is_prod: bool) {
    // Production builds get maximum compression (like `xz -9`), debug builds trade
    // some size for a much faster build.
    let preset = if is_prod { 9 } else { 6 };

    let file = File::create(payload_out).expect("failed to create payload file");
    payload::pack(release_path, file, preset)
        .and_then(|mut file| file.flush())
        .unwrap_or_else(|e| panic!("failed to pack release {}: {e}", release_path.display()));

    let size = fs::metadata(payload_out).map(|m| m.len()).unwrap_or(0);
    println!(
        "cargo::warning=Packed release into payload ({:.1} MiB compressed)",
        size as f64 / (1024.0 * 1024.0)
    );
}

fn non_empty_env(name: &str) -> Option<String> {
    env::var(name).ok().filter(|v| !v.is_empty())
}
