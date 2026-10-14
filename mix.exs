defmodule Swordfish.MixProject do
  use Mix.Project

  @version "1.3.0"

  def project do
    [
      app: :swordfish,
      version: @version,
      elixir: "~> 1.11.0",
      description:
        "Declarative AI integration for Elixir/Phoenix applications with validated queries and actions.",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      name: "Swordfish",
      test_coverage: [tool: ExCoveralls]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :ssl, :hackney]
    ]
  end

  defp deps do
    [
      {:ecto, ">= 3.1.2 and < 3.6.2"},
      {:jason, "~> 1.0"},
      {:tesla, "~> 1.4.3"},
      {:hackney, "~> 1.17.0"},
      {:nimble_parsec, "1.3.1", only: :docs, runtime: false, override: true},
      {:earmark_parser, "1.4.44", only: :docs, runtime: false, override: true},
      {:ex_doc, "0.24.0", only: :docs, runtime: false},
      {:excoveralls, "~> 0.10", only: :test}
    ]
  end

  defp package do
    [
      name: "swordfish",
      maintainers: ["Jorge Garrido"],
      licenses: ["MIT"],
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE),
      links: %{"GitHub" => "https://github.com/zgbjgg/swordfish"}
    ]
  end

  defp docs do
    [
      main: "Swordfish.LiveView",
      source_ref: "v#{@version}",
      source_url: "https://github.com/zgbjgg/swordfish"
    ]
  end
end
