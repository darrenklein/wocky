defmodule Golem.Mixfile do
  use Mix.Project

  def project do
    [app: :golem,
     version: "0.1.0",
     build_path: "../../_build",
     config_path: "../../config/config.exs",
     deps_path: "../../deps",
     lockfile: "../../mix.lock",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     test_coverage: [tool: Coverex.Task],
     aliases: [
       recompile: ["clean", "compile"],
       reset: ["ecto.drop", "ecto.create", "ecto.migrate"]
     ],
     preferred_cli_env: [
       espec: :test
     ],
     dialyzer: [
       plt_apps: [:ecto],
       plt_add_deps: :transitive,
       flags: [
         # :unmatched_returns,
         # :underspecs,
         :error_handling,
         :race_conditions
       ]
     ],
     deps: deps()]
  end

  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [extra_applications: [:logger],
     mod: {Golem.Application, []}]
  end

  defp deps do
    [
      {:ecto,       "~> 2.0"},
      {:mariaex,    "~> 0.8.1"},
      {:poolboy,    "~> 1.5"},

      {:lager,                "~> 3.2"},
      {:logger_lager_backend, "~> 0.0.2"},
      {:ossp_uuid,
        github: "hippware/erlang-ossp-uuid",
        tag: "v1.0.1",
        manager: :rebar3},

      {:espec,      "~> 1.2", only: :test},
      {:coverex,    "~> 1.4", only: :test},
      {:credo,      "~> 0.6", only: :dev, runtime: false},
      {:ex_guard,   "~> 1.1", only: :dev, runtime: false},
      {:dialyxir,   "~> 0.4", only: :dev, runtime: false},
      {:reprise,    "~> 0.5", only: :dev}
    ]
  end
end
