defmodule Roguelike.MixProject do
  use Mix.Project

  def project do
    [
      app: :roguelike,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Roguelike.Application, []}
    ]
  end

  defp deps do
    # No external dependencies!
    []
  end
end
