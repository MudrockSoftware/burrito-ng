defmodule BurritoNg.MixProject do
  use Mix.Project

  @version String.trim(File.read!("VERSION"))
  @github_url "https://github.com/MudrockSoftware/burrito-ng"

  def project do
    [
      app: :burrito_ng,
      description:
        "Burrito NG, a maintained (and incompatible) fork of Burrito. Turn your Elixir application into a simple, self-contained, single-file executable for MacOS, Linux, and Windows.",
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [
        main: "readme",
        extras: ["README.md"],
        source_url: @github_url,
        source_ref: "v#{@version}"
      ],
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :eex]
    ]
  end

  def package do
    [
      maintainers: ["MUDROCK SOFTWARE LTD"],
      name: :burrito_ng,
      licenses: ["MIT"],
      files:
        ~w(lib LICENSE VERSION mix.exs README.md .formatter.exs src bin build.rs Cargo.toml Cargo.lock),
      links: %{
        "GitHub" => @github_url,
        "Changelog" => "#{@github_url}/blob/main/CHANGELOG.md",
        "Original Project" => "https://github.com/burrito-elixir/burrito"
      }
    ]
  end

  defp deps do
    [
      {:req, ">= 0.5.0"},
      {:typed_struct, "~> 0.2.0 or ~> 0.3.0", runtime: false},
      {:jason, "~> 1.4"},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end
end
