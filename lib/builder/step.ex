defmodule BurritoNg.Builder.Step do
  @doc """
  This function is called when the step is to be executed by the build phase.
  It should return a context to be passed along to the next build step or phase.
  """
  @callback execute(BurritoNg.Builder.Context.t()) :: BurritoNg.Builder.Context.t()
end
