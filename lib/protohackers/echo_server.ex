# defmodule Protohackers.EchoServer do
#   use GenServer
#
#   require Logger
#
#   def start_link([] = _opts) do
#     GenServer.start_link(__MODULE__, :no_state)
#   end
#
#   defstruct [:listen_socket, :supervisor]
#
#   @impl true
#   def init(:no_state) do
#     {:ok, supervisor} = Task.Supervisor.start_link(max_children: 100)
#
#     listen_options = [
#       mode: :binary,
#       active: false,
#       reuseaddr: true,
#       exit_on_close: false,
#       backlog: 128,
#       packet: :line
#     ]
#
#     case :gen_tcp.listen(5001, listen_options) do
#       {:ok, listen_socket} ->
#         Logger.info("Starting echo server on port 5001")
#         state = %__MODULE__{listen_socket: listen_socket, supervisor: supervisor}
#         {:ok, state, {:continue, :accept}}
#
#       {:error, reason} ->
#         {:stop, reason}
#     end
#   end
#
#   # @impl true
#   # def handle_continue(:accept, %__MODULE__{} = state) do
#   #   case :gen_tcp.accept(state.listen_socket, 1000) do
#   #     {:ok, socket} ->
#   #       Task.Supervisor.start_child(state.supervisor, fn -> handle_connection(socket) end)
#   #       {:noreply, {:continue, :accept}}
#   #
#   #     {:error, :timeout} ->
#   #       {:noreply, state, {:continue, :accept}}
#   #
#   #     {:error, reason} ->
#   #       Logger.error("Accept error: #{inspect(reason)}")
#   #       {:stop, reason, state}
#   #   end
#   # end
#
#   @impl true
#   def handle_continue(:accept, state) do
#     # Порождаем отдельный процесс для accept, чтобы GenServer был свободен
#     spawn_link(fn -> accept_loop(state) end)
#     {:noreply, state}
#   end
#
#   defp accept_loop(state) do
#     case :gen_tcp.accept(state.listen_socket) do
#       {:ok, socket} ->
#         # Сразу запускаем обработчик в Supervisor
#         Task.Supervisor.start_child(state.supervisor, fn -> handle_connection(socket) end)
#
#         # И мгновенно возвращаемся к ожиданию следующего клиента
#         accept_loop(state)
#
#       {:error, reason} ->
#         Logger.error("Accept error: #{inspect(reason)}")
#     end
#   end
#
#   ## Helpers
#   # defp handle_connection(socket) do
#   #   case echo_loop(socket, 0) do
#   #     :ok -> :ok
#   #     {:error, :closed} -> :ok
#   #     {:error, :buffer_overflow} -> Logger.error("Buffer overflow: client sent too much")
#   #     {:error, reason} -> Logger.error("Failed to receive data: #{inspect(reason)}")
#   #   end
#   #
#   #   :gen_tcp.close(socket)
#   # end
#   defp handle_connection(socket) do
#     # Устанавливаем лимит времени на всё соединение
#     Logger.debug("New connection handled")
#
#     case echo_loop(socket, 0) do
#       :ok ->
#         Logger.info("Connection finished normally")
#
#       {:error, :buffer_overflow} ->
#         Logger.error("Closing due to overflow")
#     end
#
#     :gen_tcp.close(socket)
#   end
#
#   @limit _100_kb = 1024 * 100
#
#   defp echo_loop(socket, total_bytes) do
#     case(:gen_tcp.recv(socket, 0, 5000)) do
#       {:ok, data} ->
#         new_total = total_bytes + byte_size(data)
#
#         if new_total > @limit do
#           {:error, :buffer_overflow}
#         else
#           :gen_tcp.send(socket, data)
#           echo_loop(socket, new_total)
#         end
#
#       {:error, :closed} ->
#         :ok
#
#       {:error, :timeout} ->
#         :ok
#
#       {:error, reason} ->
#         Logger.debug("Connection error: #{inspect(reason)}")
#     end
#   end
# end
defmodule Protohackers.EchoServer do
  use GenServer

  require Logger
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  defstruct [:listen_socket, :supervisor]

  @impl true
  def init(opts) do
    port = Keyword.fetch!(opts, :port)
    {:ok, supervisor} = Task.Supervisor.start_link(max_children: 100)

    listen_options = [
      ifaddr: {0, 0, 0, 0},
      mode: :binary,
      active: false,
      reuseaddr: true,
      exit_on_close: false
    ]

    case :gen_tcp.listen(port, listen_options) do
      {:ok, listen_socket} ->
        Logger.info("Starting echo server on port 5001")
        state = %__MODULE__{listen_socket: listen_socket, supervisor: supervisor}
        {:ok, state, {:continue, :accept}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    case :gen_tcp.accept(state.listen_socket) do
      {:ok, socket} ->
        Task.Supervisor.start_child(state.supervisor, fn -> handle_connection(socket) end)
        {:noreply, state, {:continue, :accept}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  ## Helpers

  defp handle_connection(socket) do
    case recv_until_closed(socket, _buffer = "", _buffered_size = 0) do
      {:ok, data} -> :gen_tcp.send(socket, data)
      {:error, reason} -> Logger.error("Failed to receive data: #{inspect(reason)}")
    end

    :gen_tcp.close(socket)
  end

  @limit _100_kb = 1024 * 100

  defp recv_until_closed(socket, buffer, buffered_size) do
    case :gen_tcp.recv(socket, 0, 10_000) do
      {:ok, data} when buffered_size + byte_size(data) > @limit -> {:error, :buffer_overflow}
      {:ok, data} -> recv_until_closed(socket, [buffer, data], buffered_size + byte_size(data))
      {:error, :closed} -> {:ok, buffer}
      {:error, reason} -> {:error, reason}
    end
  end
end
