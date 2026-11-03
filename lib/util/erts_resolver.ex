defmodule BurritoNg.Util.ERTSResolver do
  @moduledoc """
  A module that implements the ERTSResolver behaviour is responsible for returning a target with
  a fully resolved `:erts_source` field.

  You can register your ERTS resolver as the default one by calling `BurritoNg.register_erts_resolver/1`,
  otherwise Burrito will use the `BurritoNg.Util.DefaultERTSResolver` module.
  """
  alias BurritoNg.Builder.Target
  alias BurritoNg.Util.DefaultERTSResolver

  @callback do_resolve(Target.t()) :: Target.t()

  @spec resolve(BurritoNg.Builder.Target.t()) :: Target.t()
  def resolve(%Target{} = target) do
    resolve_module = Application.get_env(:burrito_ng, :erts_resolver, DefaultERTSResolver)
    resolve_module.do_resolve(target)
  end
end
