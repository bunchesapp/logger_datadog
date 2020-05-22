defmodule LoggerDatadog do
  @moduledoc """
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
  """
  @moduledoc since: "0.1.1"

  alias LoggerDatadog.Utilities

  @behaviour :gen_event

  @default_datadog_endpoint "intake.logs.datadoghq.com"

  defstruct [:api_token,
             level: :debug,
             metadata: [],
             service: "elixir",
             socket: []]

  @doc false
  @impl true
  def init(__MODULE__), do: init({__MODULE__, []})

  @doc false
  def init({__MODULE__, opts}) do
    system_opts = Application.get_env(:logger, :datadog) || []

    {:ok, configure(Keyword.merge(system_opts, opts))}
  end

  @doc false
  @impl true
  def handle_call({:configure, options}, state),
    do: {:ok, :ok, configure(options, state)}

  @doc false
  @impl true
  def handle_event({level, gl, log}, state) when gl != node() do
    if Logger.compare_levels(level, state.level) != :lt do
      _ = send_log(level, log, state)
    end
    {:ok, state}
  end

  @doc false
  @impl true
  def handle_event(:flush, state), do: {:ok, state}

  @doc false
  defp configure(opts, state \\ %__MODULE__{}) do
    # Get Config Values
    api_token = Keyword.get(opts, :api_token, state.api_token)
    endpoint =
      case Keyword.get(opts, :endpoint, @default_datadog_endpoint) do
        binary when is_binary(binary) -> String.to_charlist(binary)
        other -> other
      end
    level = Keyword.get(opts, :level, state.level)
    metadata = Keyword.get(opts, :metadata, state.metadata)
    port = Keyword.get(opts, :port, 10514)
    service = Keyword.get(opts, :service, state.service)
    tls = Keyword.get(opts, :tls, false)

    # Require Datadog API Token
    if not is_binary(api_token) do
      raise "`:api_token` value is required in the `:logger, :datadog` config."
    end

    # Open Socket to Datadog (TCP -> TLS if configured)
    socket_options = [endpoint: endpoint, port: port, tls: tls]
    %LoggerDatadog{socket: socket} = socket_connect(socket_options, state)

    struct(state,
      api_token: api_token,
      level: level,
      metadata: metadata,
      service: service,
      socket: socket
    )
  end

  defp socket_connect([endpoint: endpoint, port: port, tls: tls], state) do
    # If a connection is already open, close to reconfigure.
    _ = for {mod, sock} <- state.socket, do: mod.close(sock)

    # Open TCP Socket
    {:ok, tcp_socket} = :gen_tcp.connect(endpoint, port, [:binary])

    # If TLS is enabled, setup SSL connection.
    # Otherwise, utilize the TCP socket.
    socket =
      if tls do
        options =
          if is_list(tls) do
            tls
          else
            [handshake: :full]
          end
        {:ok, socket} = :ssl.connect(tcp_socket, options)
        [{:ssl, socket}, {:gen_tcp, tcp_socket}]
      else
        [{:gen_tcp, tcp_socket}]
      end

    %{state | socket: socket}
  end

  defp socket_connect(nil, state) do
    opts = Application.get_env(:logger, :datadog)
    endpoint =
      case Keyword.get(opts, :endpoint, @default_datadog_endpoint) do
        binary when is_binary(binary) -> String.to_charlist(binary)
        other -> other
      end
    port = Keyword.get(opts, :port, 10514)
    tls = Keyword.get(opts, :tls, false)
    socket_connect([endpoint: endpoint, port: port, tls: tls], state)
  end

  @doc false
  defp send_log(lvl, {Logger, msg, ts, meta}, state) do
    {mod, socket} = hd(state.socket)
    {:ok, hostname} = :inet.gethostname()

    metadata =
      meta
      |> filter(state.metadata)
      |> normalize()
      |> Map.new()

    request_id = Map.get(metadata, :request_id)
    span_id = Map.get(metadata, :span_id)
    trace_id = Map.get(metadata, :trace_id)

    log_map =
      %{
        "message" => msg,
        "metadata" => metadata,
        "level" => lvl,
        "timestamp" => Utilities.ts_to_iso(ts),
        "source" => "elixir",
        "host" => List.to_string(hostname),
        "request_id" => request_id,
        "service" => state.service,
        "span_id" => span_id,
        "trace_id" => trace_id
      }

    log = Jason.encode_to_iodata!(log_map)

    try do
      case mod.send(socket, [state.api_token, " ", log, ?\r, ?\n]) do
        :ok -> :ok
        {:ok, _} -> :ok
        _ -> raise "Unable to send message to socket."
      end
    rescue
      _e ->
        try do
          socket_connect(nil, state)
          {mod, socket} = hd(state.socket)
          retry = mod.send(socket, [state.api_token, " ", log, ?\r, ?\n])
          case retry do
            :ok -> :ok
            {:ok, _} -> :ok
            _ -> {:error, :send_log_error}
          end
        catch
          _ -> {:error, :send_log_error}
        end
    end
  end

  defp filter(metadata, :all), do: metadata
  defp filter(_metadata, :none), do: []
  defp filter(_metadata, []), do: []
  defp filter(metadata, keys), do: Keyword.take(metadata, keys)

  defp normalize(list) when is_list(list) do
    if Keyword.keyword?(list) do
      Map.new(list, fn {key, value} -> {key, normalize(value)} end)
    else
      Enum.map(list, &normalize/1)
    end
  end

  defp normalize(map) when is_map(map), do:
    Utilities.flatten(map)

  defp normalize(string) when is_binary(string), do: string
  defp normalize(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp normalize(pid) when is_pid(pid), do: "#{inspect pid}"
  defp normalize(other), do: other
end
