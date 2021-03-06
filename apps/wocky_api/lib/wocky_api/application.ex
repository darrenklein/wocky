defmodule WockyAPI.Application do
  @moduledoc false

  use Application

  alias WockyAPI.Callbacks
  alias WockyAPI.Endpoint
  alias WockyAPI.Metrics.PhoenixInstrumenter
  alias WockyAPI.Metrics.PipelineInstrumenter
  alias WockyAPI.Metrics.PrometheusExporter
  alias WockyAPI.Middleware.QueryCounter
  alias WockyAPI.Middleware.QueryTimer

  @impl true
  def start(_type, _args) do
    PhoenixInstrumenter.setup()
    PipelineInstrumenter.setup()
    PrometheusExporter.setup()
    _ = QueryCounter.install(WockyAPI.Schema)
    _ = QueryTimer.install(WockyAPI.Schema)

    # Define workers and child supervisors to be supervised
    children = [
      WockyAPI.Metrics,
      # Start the endpoints when the application starts
      WockyAPI.Endpoint,
      {Absinthe.Subscription, WockyAPI.Endpoint},
      WockyAPI.Metrics.Endpoint
    ]

    opts = [strategy: :one_for_one, name: WockyAPI.Supervisor]

    Callbacks.register()

    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    Endpoint.config_change(changed, removed)
    :ok
  end
end
