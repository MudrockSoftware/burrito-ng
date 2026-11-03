# 🌯 Changelog

## v1.0.0

First release of Burrito NG, a maintained fork of [Burrito](https://github.com/burrito-elixir/burrito). Burrito NG is **not compatible** with the original Burrito.

* Differences from the original Burrito:
  * Everything is named after Burrito NG:
    * Modules: `Burrito.*` → `BurritoNg.*` (e.g. `&BurritoNg.wrap/1`, `BurritoNg.Util.Args`).
    * Release config key: `burrito:` → `burrito_ng:`.
    * Environment variables: `BURRITO_TARGET` → `BURRITO_NG_TARGET`, `__BURRITO` / `__BURRITO_BIN_PATH` → `__BURRITO_NG` / `__BURRITO_NG_BIN_PATH`.
    * Install directory: `.burrito` → `.burrito_ng`, output directory: `burrito_out/` → `burrito_ng_out/`, download cache: `burrito_ng_file_cache`.
  * The wrapper, archiver and build pipeline are written in Rust. Zig and the `xz` CLI are not used. Burrito NG needs Rust `1.85+` (`cargo`) plus the `rustup` target for each build target.
  * Plugins are Rust source files: `plugin: "./my_plugin.rs"` with `pub fn burrito_ng_plugin_entry(install_dir: &str, program_manifest_json: &str)`.
  * NIF cross-compilation uses per-target C cross compilers (musl GCC for Linux, MinGW-w64 for Windows, Xcode clang for MacOS) instead of `zig cc`. Override them with the `nif_cc`, `nif_cxx`, `nif_ar` and `nif_ranlib` target qualifiers.
  * Windows targets need the MinGW-w64 linker. Building MacOS targets from Linux needs an osxcross-style linker set through `CARGO_TARGET_<TRIPLE>_LINKER`.
  * The payload is a standard tar archive (`tar` crate), xz compressed with the pure Rust `lzma-rust2` crate, and unpacked as a stream at install time.
  * The `maintenance meta` JSON contains `rust_version` / `build_arguments`.
  * The wrapper's compiled dependencies are cached in `target/` between builds.
  * A missing toolchain for a target is reported before any build phase runs.
  * The musl runtime is written atomically at startup.

For the history of the original project, see the [Burrito changelog](https://github.com/burrito-elixir/burrito/blob/main/CHANGELOG.md).
