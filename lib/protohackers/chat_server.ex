defmodule Protohackers.ChatServer do
  use GenServer
  require Logger

  # @registry Protohackers.ChatRegistry

  def start_link(args), do: GenServer.start_link(__MODULE__, args)

  @impl true
  def init(args) do
    # port = if is_list(args), do: Keyword.get(args, :port, 5004), else: 5004
    port = Keyword.get(args, :port, 5004)
    # Сохраняем имя реестра в состоянии сервера
    registry = Keyword.get(args, :registry, Protohackers.ChatRegistry)

    # С принудительным приведением к числу
    port = args |> List.wrap() |> Keyword.get(:port, 5004)

    {:ok, supervisor} = Task.Supervisor.start_link(max_children: 100)

    case :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true, packet: :line]) do
      {:ok, listen_socket} ->
        Logger.info("Chat Server started on port #{port}")
        state = %{socket: listen_socket, supervisor: supervisor, registry: registry}
        {:ok, state, {:continue, :accept}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_port, _from, %{socket: socket} = state) do
    # :inet.port возвращает {:ok, port} для открытого сокета
    {:ok, port} = :inet.port(socket)
    {:reply, port, state}
  end

  @impl true
  def handle_continue(:accept, state) do
    spawn_link(fn -> accept_loop(state) end)
    {:noreply, state}
  end

  defp accept_loop(state) do
    {:ok, socket} = :gen_tcp.accept(state.socket)

    case Task.Supervisor.start_child(state.supervisor, fn ->
           handle_login(socket, state.registry)
         end) do
      {:ok, _pid} ->
        :ok

      {:error, :max_children} ->
        :gen_tcp.send(socket, "Server full. Try again later.\n")
        :gen_tcp.close(socket)
    end

    accept_loop(state)
  end

  # --- Логика входа ---

  defp handle_login(socket, registry) do
    :gen_tcp.send(socket, "Welcome to budgetchat! What shall I call you?\n")

    case :gen_tcp.recv(socket, 0) do
      {:ok, data} ->
        name = String.trim(data)

        if valid_name?(name) do
          enter_room(socket, name, registry)
        else
          :gen_tcp.send(socket, "Invalid name! Use only letters and numbers.\n")
          :gen_tcp.close(socket)
        end

      _ ->
        :gen_tcp.close(socket)
    end
  end

  defp valid_name?(name) do
    String.length(name) >= 1 and String.match?(name, ~r/^[[:alnum:]]+$/)
  end

  defp enter_room(socket, name, registry) do
    # 1. Получаем список тех, кто уже в чате (до нашей регистрации)
    others = get_users(registry)
    :gen_tcp.send(socket, "* The room contains: #{Enum.join(others, ", ")}\n")

    # 2. Регистрируем себя
    {:ok, _} = Registry.register(registry, "room", name)

    # 3. Оповещаем остальных
    broadcast(name, "* #{name} has entered the room", registry)

    # 4. Переходим в цикл чата
    chat_loop(socket, name, registry)

    # 5. После выхода из цикла (отключение)
    broadcast(name, "* #{name} has left the room", registry)
    :gen_tcp.close(socket)
  end

  # --- Вспомогательные функции ---

  defp get_users(registry) do
    Registry.select(registry, [{{:_, :_, :"$1"}, [], [:"$1"]}])
  end

  defp broadcast(sender_name, message, registry) do
    IO.puts("Бродкаст от #{sender_name}: #{message}")
    IO.inspect(sender_name, label: "Sender")
    IO.inspect(message, label: "Message")

    Registry.dispatch(registry, "room", fn entries ->
      # Что выведет тут?
      IO.puts(entries, label: "Found in registry")

      for {pid, name} <- entries do
        if name != sender_name do
          IO.puts("Отправка процесса PID #{inspect(pid)} для #{name}")
          send(pid, {:message, message})
        else
          IO.puts("Пропуск отправителя #{name}")
        end
      end
    end)
  end

  defp chat_loop(socket, name, registry) do
    # Здесь нам нужно одновременно ждать данных из сокета 
    # и сообщений от других процессов через почтовый ящик Elixir
    # Мы сделаем сокет активным (active: true), чтобы данные приходили как сообщения
    :inet.setopts(socket, active: true)
    receive_messages(socket, name, registry)
  end

  defp receive_messages(socket, name, registry) do
    receive do
      # Сообщение от другого пользователя (через Registry)
      {:message, msg} ->
        IO.puts("DEBUG SERVER: Process [#{name}] sending to TCP: #{msg}")
        :gen_tcp.send(socket, msg <> "\n")
        receive_messages(socket, name, registry)

      # Данные от нашего собственного сокета (пользователь что-то написал)
      {:tcp, ^socket, data} ->
        IO.puts("DEBUG: Process #{name} received TCP data: #{inspect(data)}")
        msg = String.trim(data)
        # IO.puts("DEBUG SERVER: Process [#{name}] broadcasting message: #{msg}")
        broadcast(name, "[#{name}] #{msg}", registry)
        receive_messages(socket, name, registry)

      # Сокет закрылся
      {:tcp_closed, ^socket} ->
        IO.puts("DEBUG SERVER: Process [#{name}] TCP CLOSED")
        :ok

      {:tcp_error, ^socket, _reason} ->
        :ok

      _other ->
        # IO.inspect(other, label: "DEBUG SERVER: Unexpected message")
        receive_messages(socket, name, registry)
    after
      # Тайм-аут на случай зависания (опционально)
      30_000 ->
        receive_messages(socket, name, registry)
    end
  end
end
