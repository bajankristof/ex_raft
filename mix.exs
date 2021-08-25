defmodule ExRaft.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/bajankristof/ex_raft"

  def project do
    [
      app: :ex_raft,
      version: @version,
      name: "ExRaft",
      description: "An Elixir implementation of the raft consensus protocol.",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      source_url: @source_url,
      package: package(),
      docs: [
        main: "readme",
        extras: ["README.md"],
        source_url: @source_url
      ]
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
      {:gen_state_machine, "~> 3.0"},
      {:ex_doc, "~> 0.25.1", only: :dev, runtime: false},
      {:meck, "~> 0.9.2", only: :test}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/bajankristof/ex_raft"}
    ]
  end
end
