defmodule Protohackers.PrimeServer do
  use GenServer
  require Logger

  defstruct [:listen_socket, :supervisor]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    port =
      case opts do
        p when is_integer(p) -> p
        list when is_list(list) -> Keyword.get(list, :port, 5002)
        _ -> 5002
      end

    {:ok, supervisor} = Task.Supervisor.start_link(max_children: 100)

    listen_options = [
      mode: :binary,
      active: false,
      reuseaddr: true,
      backlog: 128
    ]

    case :gen_tcp.listen(port, listen_options) do
      {:ok, listen_socket} ->
        Logger.info("Prime Server started on port #{port}")
        state = %__MODULE__{listen_socket: listen_socket, supervisor: supervisor}
        {:ok, state, {:continue, :accept}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:accept, state) do
    spawn_link(fn -> accept_loop(state) end)
    {:noreply, state}
  end

  defp accept_loop(state) do
    case :gen_tcp.accept(state.listen_socket) do
      {:ok, socket} ->
        Task.Supervisor.start_child(state.supervisor, fn -> handle_connection(socket) end)
        accept_loop(state)

      {:error, reason} ->
        Logger.error("Accept error: #{inspect(reason)}")
    end
  end

  defp handle_connection(socket) do
    receive_loop(socket, "")
    :gen_tcp.close(socket)
  end

  defp receive_loop(socket, buffer) do
    case :gen_tcp.recv(socket, 0, 10_000) do
      {:ok, data} ->
        new_buffer = buffer <> data

        case process_buffer(socket, new_buffer) do
          {:ok, remaining_buffer} ->
            receive_loop(socket, remaining_buffer)

          {:error, :malformed} ->
            :gen_tcp.send(socket, "invalid request\n")
            :ok
        end

      {:error, _} ->
        :ok
    end
  end

  defp process_buffer(socket, buffer) do
    if String.contains?(buffer, "\n") do
      [line, rest] = String.split(buffer, "\n", parts: 2)

      case handle_request(line) do
        {:ok, response_json} ->
          :gen_tcp.send(socket, response_json <> "\n")
          process_buffer(socket, rest)

        {:error, :malformed} ->
          {:error, :malformed}
      end
    else
      {:ok, buffer}
    end
  end

  defp handle_request(line) do
    case Jason.decode(line) do
      {:ok, %{"method" => "isPrime", "number" => n}} when is_number(n) ->
        response = %{"method" => "isPrime", "prime" => is_prime?(n)}
        {:ok, Jason.encode!(response)}

      _ ->
        {:error, :malformed}
    end
  end

  defp is_prime?(n) when is_integer(n) and n > 1 do
    if n == 2, do: true, else: do_is_prime?(n)
  end

  defp is_prime?(_n), do: false

  defp do_is_prime?(n) do
    limit = trunc(:math.sqrt(n))

    if limit < 2 do
      true
    else
      2..limit |> Enum.all?(fn d -> rem(n, d) != 0 end)
    end
  end
end
