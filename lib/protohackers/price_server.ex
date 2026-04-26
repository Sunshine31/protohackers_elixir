defmodule Protohackers.PriceServer do
  use GenServer
  require Logger

  # Фиксированный размер сообщения по протоколу
  @msg_size 9

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    port = Keyword.fetch!(opts, :port)

    {:ok, supervisor} = Task.Supervisor.start_link(max_children: 1000)

    listen_options = [
      ifaddr: {0, 0, 0, 0},
      mode: :binary,
      active: false,
      reuseaddr: true,
      exit_on_close: false,
      backlog: 128
    ]

    case :gen_tcp.listen(port, listen_options) do
      {:ok, listen_socket} ->
        Logger.info("Price Server started on port #{port}")
        state = %{listen_socket: listen_socket, supervisor: supervisor}
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

  ## Обработка соединения
  defp handle_connection(socket) do
    # Каждый клиент имеет свою собственную карту цен
    # Ключ: timestamp, Значение: price
    receive_loop(socket, %{})
    :gen_tcp.close(socket)
  end

  defp receive_loop(socket, prices) do
    # Читаем ровно 9 байт
    case :gen_tcp.recv(socket, @msg_size) do
      {:ok, <<type::8, val1::signed-32, val2::signed-32>>} ->
        case type do
          # Insert
          ?I ->
            new_prices = Map.put(prices, val1, val2)
            receive_loop(socket, new_prices)

          # Query
          ?Q ->
            handle_query(socket, val1, val2, prices)
            receive_loop(socket, prices)

          _ ->
            # Неизвестный тип — закрываем
            :ok
        end

      # Клиент отключился
      {:error, _} ->
        :ok
    end
  end

  defp handle_query(socket, mintime, maxtime, prices) do
    avg =
      if mintime > maxtime do
        0
      else
        # Фильтруем данные в диапазоне
        matches = for {t, p} <- prices, t >= mintime and t <= maxtime, do: p

        case length(matches) do
          0 ->
            0

          count ->
            sum = Enum.sum(matches)

            # В Elixir div делает целочисленное деление (как требует задача)
            div(sum, count)
        end
      end

    # Отправляем ответ 4 байта в формате signed 32-bit Big-Endian
    :gen_tcp.send(socket, <<avg::signed-32>>)
  end
end
