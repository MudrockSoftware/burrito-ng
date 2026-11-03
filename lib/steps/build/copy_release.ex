defmodule BurritoNg.Steps.Build.CopyRelease do
  alias BurritoNg.Builder.Context
  alias BurritoNg.Builder.Step
  alias BurritoNg.Steps.Build.PackAndBuild

  @behaviour Step

  @success_banner """
  \n\n
  🌯 Burrito NG has wrapped your Elixir app! 🌯
  """

  @impl Step
  def execute(%Context{} = context) do
    app_path = File.cwd!()
    release_name = Atom.to_string(context.mix_release.name)
    target_name = Atom.to_string(context.target.alias)

    bin_name =
      if context.target.os == :windows do
        "#{release_name}_#{target_name}.exe"
      else
        "#{release_name}_#{target_name}"
      end

    bin_path = PackAndBuild.wrapper_binary_path(context)
    bin_out_path = Path.join(app_path, ["burrito_ng_out"])
    File.mkdir_p!(bin_out_path)

    output_bin_path = Path.join(bin_out_path, [bin_name])

    # Delete the existing bin, to prevent a MacOS bug
    # where exiting bins modified in place cause SIP to be upset
    if File.exists?(output_bin_path) do
      File.rm!(output_bin_path)
    end

    File.copy!(bin_path, output_bin_path)

    if !context.mix_release.options[:burrito_ng][:no_clean] do
      PackAndBuild.clean(context)
    end

    # Mark resulting bin as executable
    File.chmod!(output_bin_path, 0o744)

    IO.puts(@success_banner <> "\tOutput Path: #{output_bin_path}\n\n")

    context
  end
end
