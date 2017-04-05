# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :ejabberd,
  keep_lager_intact: true

config :kernel,
  start_pg2: :true

config :sasl,
  sasl_error_logger: :false

config :ssl,
  session_lifetime: 600 # 10 minutes

config :mnesia,
  dir: '_build/#{Mix.env}/mnesia'

config :setup,
  verify_directories: :false

config :hut,
  level: :critical

config :lager,
  colored: :true,
  log_root: '_build/#{Mix.env}/log',
  crash_log: 'crash.log',
  handlers: [
    lager_console_backend: [
       :info,
       {:lager_default_formatter, [:time, :color, ' [', :severity, '] ', :message, '\e[0m\r\n']}
    ],
    lager_file_backend: [
      file: 'wocky.log',
      level: :warning,
      size: 2097152,
      date: '$D0',
      count: 5
    ],
    lager_file_backend: [
      file: 'debug.log',
      level: :debug,
      size: 2097152,
      date: '$D0',
      count: 5
    ]
  ],
  traces: [
    # {{:lager_file_backend, 'location.log'}, [module: Wocky.Location]},
    # {{:lager_file_backend, 'location.log'}, [module: Wocky.LocationAPI]},
    # {{:lager_file_backend, 'notifications.log'}, [
    #   module: Wocky.Notification.AWSHandler
    # ]},
    # {{:lager_file_backend, 'notifications.log'}, [
    #   module: Wocky.Notification.NullHandler
    # ]},
    # {{:lager_file_backend, 'notifications.log'}, [
    #   module: :mod_wocky_notifications
    # ]},
    # {{:lager_file_backend, 'notifications.log'}, [
    #   module: :wocky_notification_handler
    # ]}
  ]

import_config "#{Mix.env}.exs"