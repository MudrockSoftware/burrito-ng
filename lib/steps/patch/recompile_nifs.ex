defmodule BurritoNg.Steps.Patch.RecompileNIFs do
  alias BurritoNg.Builder.Context
  alias BurritoNg.Builder.Log
  alias BurritoNg.Builder.Step
  alias BurritoNg.Builder.Target

  @behaviour Step

  @impl Step
  def execute(%Context{} = context) do
    cflags = Keyword.get(context.target.qualifiers, :nif_cflags, "")
    cxxflags = Keyword.get(context.target.qualifiers, :nif_cxxflags, "")
    nif_env = Keyword.get(context.target.qualifiers, :nif_env, [])
    nif_make_args = Keyword.get(context.target.qualifiers, :nif_make_args, [])
    skip_nifs? = Keyword.get(context.target.qualifiers, :skip_nifs, false)

    if context.target.cross_build and not skip_nifs? do
      {:local_unpacked, path: erts_location} = context.target.erts_source

      nifs = nif_sniff() |> Enum.filter(fn {_, _, nif?} -> nif? end)

      if nifs != [] do
        toolchain = toolchain!(context.target)

        Enum.each(nifs, fn dep ->
          maybe_recompile_nif(
            dep,
            context.work_dir,
            erts_location,
            context.target,
            toolchain,
            cflags,
            cxxflags,
            nif_env,
            nif_make_args
          )
        end)
      end
    end

    context
  end

  @doc """
  Returns the C toolchain used to cross-compile NIFs for `target`, as a map with
  `:cc`, `:cxx`, `:ar` and `:ranlib` commands.

  Each one can be overridden per-target with the `:nif_cc`, `:nif_cxx`, `:nif_ar` and
  `:nif_ranlib` qualifiers. Otherwise a cross toolchain is looked up in `PATH`:

    * Linux: musl cross compilers, `<cpu>-unknown-linux-musl-gcc` or `<cpu>-linux-musl-gcc`
    * Windows: MinGW-w64, `<cpu>-w64-mingw32-gcc`
    * macOS: Xcode's `clang` (only when building on macOS)
  """
  @spec toolchain!(Target.t()) :: %{
          cc: String.t(),
          cxx: String.t(),
          ar: String.t(),
          ranlib: String.t()
        }
  def toolchain!(%Target{} = target) do
    defaults = default_toolchain(target)
    q = target.qualifiers

    toolchain = %{
      cc: q[:nif_cc] || defaults[:cc],
      cxx: q[:nif_cxx] || defaults[:cxx],
      ar: q[:nif_ar] || defaults[:ar],
      ranlib: q[:nif_ranlib] || defaults[:ranlib]
    }

    cc_exe = toolchain.cc && toolchain.cc |> String.split() |> List.first()

    if cc_exe == nil or System.find_executable(cc_exe) == nil do
      Log.error(
        :step,
        """
        Could not find a C compiler to cross-compile NIFs for #{target.os}/#{target.cpu} (tried: #{inspect(toolchain.cc || defaults[:tried])}).
        #{toolchain_hint(target)}
        You can also point Burrito NG at a compiler with the `:nif_cc` / `:nif_cxx` target qualifiers, or skip NIF recompilation with `skip_nifs: true`.
        """
      )

      raise "No C toolchain for NIF cross-compilation"
    end

    toolchain
  end

  defp default_toolchain(%Target{os: :linux, cpu: cpu}) do
    candidates = ["#{cpu}-unknown-linux-musl-", "#{cpu}-linux-musl-"]
    prefixed_toolchain(candidates)
  end

  defp default_toolchain(%Target{os: :windows, cpu: cpu}) do
    prefixed_toolchain(["#{cpu}-w64-mingw32-"])
  end

  defp default_toolchain(%Target{os: :darwin, cpu: cpu}) do
    if BurritoNg.Util.get_current_os() == :darwin do
      clang_target = "-target #{cpu}-apple-macos11"
      %{cc: "clang #{clang_target}", cxx: "clang++ #{clang_target}", ar: "ar", ranlib: "ranlib"}
    else
      %{tried: "an osxcross toolchain (set :nif_cc)"}
    end
  end

  defp prefixed_toolchain(prefixes) do
    case Enum.find(prefixes, &System.find_executable(&1 <> "gcc")) do
      nil ->
        %{tried: Enum.map(prefixes, &(&1 <> "gcc"))}

      prefix ->
        %{
          cc: prefix <> "gcc",
          cxx: prefix <> "g++",
          ar: prefix <> "ar",
          ranlib: prefix <> "ranlib"
        }
    end
  end

  defp toolchain_hint(%Target{os: :linux}) do
    "Install a musl cross toolchain, e.g. from https://github.com/cross-tools/musl-cross (Linux) or `brew install messense/macos-cross-toolchains/<cpu>-unknown-linux-musl` (macOS)."
  end

  defp toolchain_hint(%Target{os: :windows}) do
    "Install MinGW-w64 (Debian/Ubuntu: `apt install mingw-w64`, macOS: `brew install mingw-w64`)."
  end

  defp toolchain_hint(%Target{os: :darwin}) do
    "Cross-compiling macOS NIFs from a non-macOS host requires an osxcross toolchain."
  end

  defp nif_link_flags(%Target{os: :darwin}), do: "-O2 -fPIC -shared -undefined dynamic_lookup"
  defp nif_link_flags(%Target{os: :windows}), do: "-O2 -shared"
  defp nif_link_flags(%Target{}), do: "-O2 -fPIC -shared"

  def nif_sniff() do
    # The current procedure for finding out if a dependency has a NIF:
    # - List all deps in the project using Mix.Project.deps_paths/0
    #   - Iterate over those, and use Mix.Project.in_project/4 to execute a function inside their project context
    #   - Check if they contain :elixir_make in their `:compilers`
    #
    # We'll probably need to expand how we detect NIFs, but :elixir_make is a popular way to compile NIFs
    # so it's a good place to start...

    paths = Mix.Project.deps_paths() |> Enum.filter(fn {name, _} -> name != :burrito_ng end)

    Enum.map(paths, fn {dep_name, path} ->
      Mix.Project.in_project(dep_name, path, fn module ->
        if module && Keyword.has_key?(module.project(), :compilers) do
          {dep_name, path, Enum.member?(module.project()[:compilers], :elixir_make)}
        else
          {dep_name, path, false}
        end
      end)
    end)
  end

  defp maybe_recompile_nif(
         {dep, path, true},
         release_working_path,
         erts_path,
         %Target{} = target,
         toolchain,
         extra_cflags,
         extra_cxxflags,
         extra_env,
         extra_make_args
       ) do
    dep = Atom.to_string(dep)
    cross_target = "#{target.os}/#{target.cpu}"

    Log.info(:step, "Going to recompile NIF for cross-build: #{dep} -> #{cross_target}")

    output_priv_dir =
      Path.join(release_working_path, ["lib/#{dep}*/"])
      |> Path.expand()
      |> Path.wildcard()
      |> List.first()

    _ = System.cmd("make", ["clean"], cd: path, stderr_to_stdout: true, into: IO.stream())

    # Compose env variables for cross-compilation
    erts_env = erts_make_env(erts_path)

    # This currently is only designed for elixir_make NIFs
    build_result =
      System.cmd("make", ["all", "--always-make"] ++ extra_make_args,
        cd: path,
        stderr_to_stdout: true,
        env:
          [
            {"MIX_APP_PATH", output_priv_dir},
            {"RANLIB", toolchain.ranlib},
            {"AR", toolchain.ar},
            {"CC", "#{toolchain.cc} #{nif_link_flags(target)} #{extra_cflags}"},
            {"CXX", "#{toolchain.cxx} #{nif_link_flags(target)} #{extra_cxxflags}"}
          ] ++ crosscompile_env(target, toolchain) ++ erts_env ++ extra_env,
        into: IO.stream()
      )

    case build_result do
      {_, 0} ->
        Log.info(:step, "Successfully re-built #{dep} for #{cross_target}!")

        src_priv_files =
          Path.join(output_priv_dir, ["priv/*"]) |> Path.expand() |> Path.wildcard()

        final_output_priv_dir = Path.join(output_priv_dir, "priv")

        Enum.each(src_priv_files, fn file ->
          file_name = Path.basename(file)

          if Path.extname(file_name) == ".so" && target.os == :windows do
            new_file_name = String.replace_trailing(file_name, ".so", ".dll")
            dst_fullpath = Path.join(final_output_priv_dir, new_file_name)

            Log.info(:step, "#{file} -> #{dst_fullpath}")

            File.rename!(file, dst_fullpath)
          else
            file_name
          end
        end)

      {_output, _non_zero} ->
        Log.error(:step, "Failed to rebuild #{dep} for #{cross_target}!")
        exit(1)
    end
  end

  # NIF Makefiles (exqlite, Nerves-style ones, ...) pick host-specific linker flags from
  # `uname -s` unless CROSSCOMPILE is set, e.g. `-undefined dynamic_lookup` on a macOS host,
  # which GNU ld rejects when targeting Linux. Following the Nerves convention, its value is
  # the toolchain prefix without the trailing dash.
  defp crosscompile_env(%Target{os: os}, toolchain) do
    if os == BurritoNg.Util.get_current_os() do
      []
    else
      cc = toolchain.cc |> String.split() |> List.first()
      [{"CROSSCOMPILE", String.replace_suffix(cc, "-gcc", "")}]
    end
  end

  defp erts_make_env(erts_path) do
    ei_include =
      Path.join(erts_path, ["otp*/", "usr/", "include/"])
      |> Path.expand()
      |> Path.wildcard()
      |> List.first()

    ei_lib =
      Path.join(erts_path, ["otp*/", "usr/", "lib/"])
      |> Path.expand()
      |> Path.wildcard()
      |> List.first()

    erts_include =
      Path.join(erts_path, ["otp*/", "erts*/", "include/"])
      |> Path.expand()
      |> Path.wildcard()
      |> List.first()

    [
      {"ERL_EI_INCLUDE_DIR", ei_include},
      {"ERL_EI_LIBDIR", ei_lib},
      {"ERL_INTERFACE_INCLUDE_DIR", ei_include},
      {"ERL_INTERFACE_LIB_DIR", ei_lib},
      {"ERTS_INCLUDE_DIR", erts_include}
    ]
  end
end
