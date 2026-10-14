defmodule Swordfish.MixProject do
  use Mix.Project

  def project do
    [
      app: :swordfish,
      version: "1.3.0",
      elixir: "~> 1.11.0",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:hackney, "~> 1.17.0"}
    ]
  end
end
