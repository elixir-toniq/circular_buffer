defmodule CircularBuffer.MixProject do
  use Mix.Project

  @version "1.0.0"
  @description "General purpose circular buffer"
  @source_url "https://github.com/elixir-toniq/circular_buffer"

  def project do
    [
      app: :circular_buffer,
      version: @version,
      elixir: "~> 1.8",
      deps: deps(),
      description: @description,
      package: package(),
      source_url: @source_url,
      docs: docs(),
      dialyzer: dialyzer()
    ]
  end

  def application do
    []
  end

  defp deps do
    [
      {:propcheck, "~> 1.2", only: [:dev, :test]},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.19", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      files: [
        "CHANGELOG.md",
        "lib",
        "LICENSES",
        "mix.exs",
        "README.md",
        "REUSE.toml"
      ],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "REUSE Compliance" =>
          "https://api.reuse.software/info/github.com/elixir-toniq/circular_buffer"
      }
    ]
  end

  defp docs do
    [
      extras: ["CHANGELOG.md"],
      main: "CircularBuffer",
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  defp dialyzer() do
    [
      flags: [:missing_return, :extra_return, :unmatched_returns, :error_handling]
    ]
  end
end
