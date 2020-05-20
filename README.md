# LoggerDatadog
*Current Version:* v0.1.1

## Installation
- Add the @BunchesApp version of LoggerDatadog to your mix file with `{:logger_datadog, git: "https://github.com/bunchesapp/logger_datadog", branch: "master"}`
- Add LoggerDatadog to your application logger's backends in your config: `config :logger, backends: [:console, LoggerDatadog]`
- Configure LoggerDatadog with your API token: `config :logger, :datadog, api_token: "Y0urAp1t0k3nH3r3"`

## Configuration options:
- API Token (`:api_token`): Datadog api token. Find this in Datadog in Integrations -> API. This is a required value for LoggerDatadog, and is set to `null` initially.
- Endpoint (`:endpoint`): Datadog endpoint of the intake service being used. The default is Datadog's default endpoint of `intake.logs.datadoghq.com`.
- Level (`:level`): Logger level that should be sent to Datadog. Options are one of the following values, in ascending priority: [`:debug`/`:all`, `:info`, `:notice`, `:warning`, `:error`, `:critical`, `:alert`, `:emergency`]. `:none` is also a valid option. `:debug` is the default value.
- Metadata (`:metadata`): Metadata that gets logged alongside the actual log value.
- Port (`:port`): Datadog port of the intake service being used. The default is Datadog's default value of `10514`.
- Service (`:service`): Name of the service that's being logged. Typically, this is the name of your application in string format. `"elixir"` is the default value.
- TLS (`:tls`): If set, contains TLS configuration options for SSL connection with Datadog. `false` is the default value. See Erlang's `:ssl` docs [here](https://erlang.org/doc/man/ssl.html#type-tls_client_option) for more information on configuring TLS.
