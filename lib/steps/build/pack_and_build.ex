defmodule BurritoNg.Steps.Build.PackAndBuild do
  alias BurritoNg.Builder.Context
  alias BurritoNg.Builder.Log
  alias BurritoNg.Builder.Step
  alias BurritoNg.Builder.Target

  @behaviour Step

  @wrapper_bin_name "burrito_ng_wrapper"

  @impl Step
  def execute(%Context{} = context) do
    options = context.mix_release.options[:burrito_ng] || []
    release_name = Atom.to_string(context.mix_release.name)
    triple = Target.rust_triple(context.target)

    plugin_path = maybe_get_plugin_path(options[:plugin])

    linker_env = check_toolchain!(context.target)

    cargo_args =
      ["build", "--locked", "--target", triple, "--target-dir", target_dir(context)] ++
        if(release_build?(context.target), do: ["--release"], else: [])

    metadata_path = create_metadata_file(context, cargo_args)

    # TODO: Why do we need to do this???
    # This is to bypass a VERY strange bug inside Linux containers...
    # If we don't do this, the archiver will fail to see all the files inside the lib directory
    # This is still under investigation, but touching a file inside the directory seems to force the
    # File system to suddenly "wake up" to all the files inside it.
    Path.join(context.work_dir, ["/lib", "/.burrito_ng"]) |> File.touch!()

    build_env =
      [
        {"__BURRITO_NG_IS_PROD", if(release_build?(context.target), do: "1", else: "0")},
        {"__BURRITO_NG_RELEASE_PATH", context.work_dir},
        {"__BURRITO_NG_RELEASE_NAME", release_name},
        {"__BURRITO_NG_METADATA_PATH", metadata_path},
        {"__BURRITO_NG_PLUGIN_PATH", plugin_path}
      ] ++ linker_env ++ context.extra_build_env

    Log.info(:step, "Cargo build env: #{inspect(build_env)}")
    Log.info(:step, "Building wrapper and embedding payload for #{triple}... 🌯")

    build_result =
      System.cmd("cargo", cargo_args,
        cd: context.self_dir,
        env: build_env,
        stderr_to_stdout: true,
        into: IO.stream()
      )

    File.rm(metadata_path)

    case build_result do
      {_, 0} ->
        context

      _ ->
        Log.error(
          :step,
          "Burrito NG failed to wrap up your app! Check the logs for more information."
        )

        raise "Wrapper build failed"
    end
  end

  @doc """
  Verifies the Rust toolchain can build a wrapper for `target`, raising with
  instructions if not. Returns the linker environment to pass to Cargo.

  Called before any phase runs, so a missing toolchain fails the build early.
  """
  @spec check_toolchain!(Target.t()) :: list({String.t(), String.t()})
  def check_toolchain!(%Target{} = target) do
    triple = Target.rust_triple(target)
    ensure_rust_target_installed!(triple)
    linker_env!(target, triple)
  end

  @doc """
  The Cargo target directory used for wrapper builds. It is kept between builds so
  the wrapper's dependencies are only compiled once.
  """
  @spec target_dir(Context.t()) :: String.t()
  def target_dir(%Context{} = context) do
    Path.join(context.self_dir, "target")
  end

  @doc """
  Path of the wrapper binary produced by `execute/1` for the context's target.
  """
  @spec wrapper_binary_path(Context.t()) :: String.t()
  def wrapper_binary_path(%Context{} = context) do
    profile = if release_build?(context.target), do: "release", else: "debug"
    ext = if context.target.os == :windows, do: ".exe", else: ""

    Path.join([
      target_dir(context),
      Target.rust_triple(context.target),
      profile,
      @wrapper_bin_name <> ext
    ])
  end

  @doc """
  Removes the build outputs of the wrapper crate (including the embedded payload)
  for the context's target, keeping its compiled dependencies cached.
  """
  @spec clean(Context.t()) :: :ok
  def clean(%Context{} = context) do
    Log.info(:step, "Cleaning up...")

    args =
      [
        "clean",
        "--package",
        @wrapper_bin_name,
        "--target",
        Target.rust_triple(context.target),
        "--target-dir",
        target_dir(context)
      ] ++ if(release_build?(context.target), do: ["--release"], else: [])

    System.cmd("cargo", args, cd: context.self_dir, stderr_to_stdout: true)

    Enum.each(context.extra_build_env, fn
      {"__BURRITO_NG_MUSL_RUNTIME_FILE", path} -> File.rm(path)
      _ -> :ok
    end)

    :ok
  end

  defp maybe_get_plugin_path(nil), do: nil

  defp maybe_get_plugin_path(plugin_path) do
    path = Path.join(File.cwd!(), [plugin_path])

    if Path.extname(path) != ".rs" do
      Log.error(
        :step,
        "Burrito NG plugins must be Rust source files (`.rs`), got: #{plugin_path}. See the README for the plugin interface."
      )

      raise "Invalid Burrito NG plugin"
    end

    path
  end

  defp create_metadata_file(%Context{} = context, cargo_args) do
    Log.info(:step, "Generating wrapper metadata file...")

    release = context.mix_release

    rust_version =
      case System.cmd("rustc", ["--version"], stderr_to_stdout: true) do
        {version, 0} -> String.trim(version)
        _ -> "unknown"
      end

    metadata_map = %{
      app_name: Atom.to_string(release.name),
      rust_version: rust_version,
      build_arguments: cargo_args,
      app_version: release.version,
      options: inspect(release.options),
      erts_version: release.erts_version |> to_string()
    }

    path = context.work_dir <> "_metadata.json"
    File.write!(path, Jason.encode!(metadata_map))
    path
  end

  defp release_build?(%Target{debug?: debug?}) do
    cond do
      debug? -> false
      Mix.env() == :prod -> true
      true -> false
    end
  end

  # Make sure the Rust standard library for the target is installed (when using rustup).
  defp ensure_rust_target_installed!(triple) do
    if System.find_executable("rustup") do
      case System.cmd("rustup", ["target", "list", "--installed"], stderr_to_stdout: true) do
        {output, 0} ->
          if triple not in String.split(output) do
            Log.error(
              :step,
              "The Rust target `#{triple}` is not installed! Install it with: `rustup target add #{triple}`"
            )

            raise "Missing Rust target #{triple}"
          end

        _ ->
          :ok
      end
    end

    :ok
  end

  # Picks a linker for the wrapper binary, unless the user already configured one
  # through the standard `CARGO_TARGET_<TRIPLE>_LINKER` environment variable.
  defp linker_env!(%Target{} = target, triple) do
    var = "CARGO_TARGET_#{triple |> String.upcase() |> String.replace("-", "_")}_LINKER"

    if System.get_env(var) do
      []
    else
      default_linker!(target, triple, var)
    end
  end

  # Linux wrappers are static musl binaries; Rust ships everything needed to link
  # those, so the bundled `rust-lld` works from any host.
  defp default_linker!(%Target{os: :linux}, _triple, var), do: [{var, "rust-lld"}]

  defp default_linker!(%Target{os: :darwin}, triple, var) do
    if BurritoNg.Util.get_current_os() == :darwin do
      []
    else
      Log.error(
        :step,
        """
        Building macOS (#{triple}) wrappers from a non-macOS host requires a macOS linker and SDK (e.g. osxcross).
        Point Cargo at it with: `export #{var}=/path/to/osxcross/bin/#{triple}-clang`
        """
      )

      raise "No linker for #{triple}"
    end
  end

  defp default_linker!(%Target{os: :windows}, triple, var) do
    linker =
      case triple do
        "aarch64-pc-windows-gnullvm" -> "aarch64-w64-mingw32-clang"
        _ -> "#{triple |> String.split("-") |> hd()}-w64-mingw32-gcc"
      end

    if System.find_executable(linker) do
      [{var, linker}]
    else
      Log.error(
        :step,
        """
        Building Windows (#{triple}) wrappers requires the MinGW-w64 toolchain (`#{linker}`), which we couldn't find in your PATH.
        Install it (Debian/Ubuntu: `apt install mingw-w64`, macOS: `brew install mingw-w64`) or set `#{var}`.
        """
      )

      raise "No linker for #{triple}"
    end
  end
end
