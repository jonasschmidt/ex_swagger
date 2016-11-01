defmodule ExSwagger.Mixfile do
  use Mix.Project

  def project do
    [
      app: :ex_swagger,
      version: "0.1.0",
      elixir: "~> 1.2",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        "coveralls": :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.travis": :test,
      ]
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:ex_json_schema, git: "https://github.com/jonasschmidt/ex_json_schema.git", branch: "validation-errors"},
      {:poison, "~> 3.0", only: :test},
      {:excoveralls, "~> 0.5", only: :test},
      {:mix_test_watch, "~> 0.2.6", only: [:dev, :test]}
    ]
  end
end
