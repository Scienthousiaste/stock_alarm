defmodule StockAlarm.MixProject do
  use Mix.Project

  def project do
    [
      app: :stock_alarm,
      version: "0.1.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp escript do
    [main_module: StockAlarm.CLI]
  end

  defp deps do
    [
      {:httpoison, "~> 2.0"},
      {:floki, "~> 0.34.0"},
      {:jason, "~> 1.4"}
    ]
  end
end
