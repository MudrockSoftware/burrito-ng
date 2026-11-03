# ExampleCliApp

This is an example usage of [Burrito NG](https://github.com/MudrockSoftware/burrito-ng), for cross-compiling an Elixir application for distribution.

## Usage

1) Install dependencies: `mix deps.get`
2) Build a release:
    - In debug mode: `mix release`
    - In production mode: `MIX_ENV=prod mix release` 
4) Execute the compiled binary: `burrito_out/example_cli_app_native`
