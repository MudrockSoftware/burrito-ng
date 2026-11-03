defmodule BurritoNg do
  alias BurritoNg.Builder
  alias BurritoNg.Builder.Log

  # Minimum Rust version required to build the wrapper (keep in sync with Cargo.toml `rust-version`)
  @rust_version_min %Version{major: 1, minor: 85, patch: 0}
  @openssl_version %Version{major: 3, minor: 5, patch: 1}
  @musl_version %Version{major: 1, minor: 2, patch: 5}

  @spec wrap(Mix.Release.t()) :: Mix.Release.t()
  def wrap(%Mix.Release{} = release) do
    pre_check()
    Builder.build(release)
  end

  @spec register_erts_resolver(module()) :: :ok
  def register_erts_resolver(module) when is_atom(module) do
    Application.put_env(:burrito_ng, :erts_resolver, module)
  end

  @spec get_versions() :: map()
  def get_versions() do
    %{
      rust: @rust_version_min,
      openssl: @openssl_version,
      musl: @musl_version
    }
  end

  defp pre_check() do
    if System.find_executable("cargo") == nil do
      Log.error(
        :build,
        "You MUST have the Rust toolchain (`cargo`) installed to use Burrito, we couldn't find it in your PATH! See https://rustup.rs"
      )

      exit(1)
    end

    if Enum.all?(~w(7z 7zz), &(System.find_executable(&1) == nil)) do
      Log.warning(
        :build,
        "We couldn't find 7z/7zz in your PATH, 7z/7zz is required to build Windows releases. They will fail if you don't fix this!"
      )
    end

    check_rust_version()
  end

  defp check_rust_version() do
    with {res, 0} <- System.cmd("rustc", ["--version"], stderr_to_stdout: true),
         [_, version_string] <- Regex.run(~r/^rustc (\d+\.\d+\.\d+)/, res),
         {:ok, version} <- Version.parse(version_string) do
      if Version.compare(version, @rust_version_min) == :lt do
        Log.error(
          :build,
          "Your Rust version is too old for Burrito! We need at least `#{Version.to_string(@rust_version_min)}`, you have: `#{Version.to_string(version)}`. Try `rustup update`."
        )

        exit(1)
      end
    else
      _ ->
        Log.warning(:build, "Could not determine your Rust version, continuing anyway...")
    end
  end
end
