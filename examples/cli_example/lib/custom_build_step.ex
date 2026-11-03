defmodule ExampleCliApp.CustomBuildStep do
  alias BurritoNg.Builder.Step
  @behaviour Step

  @impl Step
  def execute(% BurritoNg.Builder.Context{} = context) do
    IO.puts("Custom build step!")
    IO.puts("Current Target: #{inspect(context.target)}")

    context
  end
end
