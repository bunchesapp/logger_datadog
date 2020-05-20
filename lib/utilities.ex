defmodule LoggerDatadog.Utilities do
  def ts_to_iso({{year, month, day}, {hour, min, sec, msec}}) do
    List.to_string(
      :io_lib.format('~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B.~3..0BZ',[year, month, day, hour, min, sec, msec])
    )
  end

  defimpl String.Chars, for: PID do
    def to_string(pid) do
      info = Process.info pid
      name = info[:registered_name]

      "#{name}-#{inspect pid}"
    end
  end

  def flatten(%{} = original_map) do
    original_map
    |> Map.to_list()
    |> to_flat_map(%{})
  end
  defp to_flat_map([{_k, %{} = v} | t], acc), do: to_flat_map(Map.to_list(v), to_flat_map(t, acc))
  defp to_flat_map([{k, v} | t], acc), do: to_flat_map(t, Map.put_new(acc, k, v))
  defp to_flat_map([], acc), do: acc
end
