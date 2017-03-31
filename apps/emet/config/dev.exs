use Mix.Config

config :wocky,
  wocky_env: 'dev'

config :lager,
  extra_sinks: [
    error_logger_lager_event: [
      handlers: [
        lager_file_backend: [file: 'error_logger.log', level: :info]
      ]
    ]
  ]

config :honeybadger,
  environment_name: "Development"

# We don't actually want this to do anything, but having it here verifies that
# crone will start up correctly
config :crone,
  tasks: [
    {"localhost", {
       {:weekly, :sun, {12, :am}},
       {:wocky_slack, :post_bot_report, ["report-testing", 7]}
     }}
   ]
