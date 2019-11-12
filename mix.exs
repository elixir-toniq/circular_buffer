defmodule CircularBuffer.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :circular_buffer,
      version: @version,
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "CircularBuffer",
      source_url: "https://github.com/keathley/circular_buffer",
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:propcheck, "~> 1.2", only: [:dev, :test]},
      {:ex_doc, "~> 0.19", only: [:dev, :test]}
    ]
  end

  def description do
    """
    General purpose circular buffer.
    """
  end

  def package do
    [
      name: "circular_buffer",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/keathley/circular_buffer"}
    ]
  end

  def docs do
    [
      source_ref: "v#{@version}",
      source_url: "https://github.com/keathley/circular_buffer",
      main: "CircularBuffer"
    ]
  end
end
