defmodule LoggerDatadog do
  @moduledoc """
  Documentation for LoggerDatadog.
  """

  @behaviour :gen_event

  defstruct [:api_token, level: :debug, metadata: [], service: "elixir", socket: []]

  @impl true
  def init(__MODULE__), do: init({__MODULE__, []})

  def init({__MODULE__, opts}) do
    system_opts = Application.get_env(:logger, :datadog) || []

    {:ok, configure(Keyword.merge(system_opts, opts))}
  end

  @impl true
  def handle_call({:configure, options}, state),
    do: {:ok, :ok, configure(options, state)}

  @impl true
  def handle_event({level, gl, log}, state) when gl != node() do
    if Logger.compare_levels(level, state.level) != :lt do
      :ok = send_log(level, log, state)
    end

    {:ok, state}
  end

  def handle_event(:flush, state), do: {:ok, state}

  defp send_log(lvl, {Logger, msg, ts, meta}, state) do
    {mod, socket} = hd(state.socket)
    {:ok, hostname} = :inet.gethostname()

    metadata =
      meta
      |> normalise()
      |> Map.new()

    data = if Map.has_key?(metadata, "query_name") do
        Jason.encode_to_iodata!(%{
          "message" => Keyword.has_key?(metadata, "query_name"),
          "metadata" => metadata,
          "level" => lvl,
          "timestamp" => ts_to_iso(ts),
          "source" => "elixir",
          "host" => List.to_string(hostname),
          "service" => state.service,
          "trace_id" => metadata.trace_id,
          "span_id" => metadata.span_id
        })
    else
        Jason.encode_to_iodata!(%{
          "message" => msg,
          "metadata" => metadata,
          "level" => lvl,
          "timestamp" => ts_to_iso(ts),
          "source" => "elixir",
          "host" => List.to_string(hostname),
          "service" => state.service
        })
    end

    send = mod.send(socket, [state.api_token, " ", data, ?\r, ?\n])
    IO.inspect data
    case send do
      :ok -> :ok
      _ -> {:error, :logging_error}
    end
  end

  defp configure(opts, state \\ %__MODULE__{}) do
    _ = for {mod, sock} <- state.socket, do: mod.close(sock)

    token = Keyword.get(opts, :api_token, state.api_token)
    service = Keyword.get(opts, :service, state.service)
    level = Keyword.get(opts, :level, state.level)
    metadata = Keyword.get(opts, :metadata, state.metadata)
    tls = Keyword.get(opts, :tls, false)
    port = Keyword.get(opts, :port, 10514)

    endpoint =
      case Keyword.get(opts, :endpoint, "intake.logs.datadoghq.com") do
        binary when is_binary(binary) -> String.to_charlist(binary)
        other -> other
      end

    if not is_binary(token) do
      raise "`api_token` value is required"
    end

    {:ok, tcp_socket} = :gen_tcp.connect(endpoint, port, [:binary])

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

    struct(state,
      socket: socket,
      api_token: token,
      service: service,
      level: level,
      metadata: metadata
    )
  end

  defp ts_to_iso({{year, month, day}, {hour, min, sec, msec}}) do
    List.to_string(
      :io_lib.format('~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B.~3..0BZ', [
        year,
        month,
        day,
        hour,
        min,
        sec,
        msec
      ])
    )
  end

  defp filter(metadata, :all), do: metadata
  defp filter(_metadata, []), do: []
  defp filter(metadata, keys), do: Keyword.take(metadata, keys)

  defp normalise(list) when is_list(list) do
    IO.puts "LIST"
    IO.inspect list
    if Keyword.keyword?(list) do
      Map.new(list, &struct_normalise/1)
    else
      Enum.map(list, &normalise/1)
    end
  end

  def struct_normalise({key, value}) do
    if key != nil do
      if not is_map(value) do
        {key, normalise(value)}
      else
        {key, value}
      end
    else
      {normalise(value)}
    end
  end

  defp normalise(map) when is_map(map) do
    IO.puts "MAP"
    IO.inspect map
    Map.new(map, &normalise/1)
  end

  defp normalise(string) when is_binary(string) do
    IO.puts "STRING"
    IO.inspect string
    string
  end

  defp normalise(atom) when is_atom(atom) do
    IO.puts "ATOM"
    IO.inspect atom
    atom
  end

  defp normalise(other), do: inspect(other)
end


{:graphql_query, %{params: %{bunch_id: "f49d8343-77be-4dc8-ad01-dfa21abb7d2e"}, query_name: "Query: Fetch Messages No From/To"}}
