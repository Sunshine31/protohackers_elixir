defmodule Protohackers.ChatServerTest do
  # Ставим false для надежности портов
  use ExUnit.Case, async: false

  setup do
    registry_id = :erlang.unique_integer([:positive])
    registry_name = Module.concat(__MODULE__, "Registry#{registry_id}")

    start_supervised!({Registry, keys: :duplicate, name: registry_name})
    {:ok, server} = Protohackers.ChatServer.start_link(port: 0, registry: registry_name)
    port = GenServer.call(server, :get_port)

    {:ok, port: port, registry: registry_name}
  end

  test "рассылка сообщений и уведомлений", %{port: port} do
    {:ok, s1} = connect_and_login(port, "Alice")
    {:ok, s2} = connect_and_login(port, "Bob")

    # Ждем уведомления для Алисы
    assert_receive_line(s1, "has entered the room")

    # Алиса пишет сообщение
    :ok = :gen_tcp.send(s1, "Hello Bob\n")

    # Боб должен получить сообщение
    assert_receive_line(s2, "[Alice] Hello Bob")

    :gen_tcp.close(s1)
    :gen_tcp.close(s2)
  end

  test "уведомление при выходе пользователя", %{port: port} do
    {:ok, s1} = connect_and_login(port, "Alice")
    {:ok, s2} = connect_and_login(port, "Bob")

    # Даем серверу время обработать входы
    Process.sleep(50)
    flush_socket(s1)
    flush_socket(s2)

    # Алиса уходит
    :ok = :gen_tcp.close(s1)

    # Боб должен увидеть системное сообщение
    assert_receive_line(s2, "has left the room")
    :gen_tcp.close(s2)
  end

  test "лимит на 100 одновременных подключений", %{port: port} do
    sockets =
      for i <- 1..100 do
        {:ok, s} = connect_and_login(port, "User#{i}")
        s
      end

    {:ok, s101} = :gen_tcp.connect(~c"localhost", port, [:binary, active: false, packet: :line])
    assert_receive_line(s101, "Server full")

    Enum.each(sockets, &:gen_tcp.close/1)
    :gen_tcp.close(s101)
  end

  # --- Helpers ---

  defp connect_and_login(port, name) do
    {:ok, s} = :gen_tcp.connect(~c"localhost", port, [:binary, active: false, packet: :line])

    # Вычитываем приветствие и список, пока не дойдем до конца логина
    # Welcome...
    _ = :gen_tcp.recv(s, 0, 500)
    :ok = :gen_tcp.send(s, "#{name}\n")
    # The room contains...
    _ = :gen_tcp.recv(s, 0, 500)

    {:ok, s}
  end

  defp assert_receive_line(socket, expected) do
    # Увеличиваем таймаут до 2000мс для стабильности в CI/медленных средах
    case :gen_tcp.recv(socket, 0, 2000) do
      {:ok, data} ->
        IO.puts("LOG: Получено '#{String.trim(data)}', ищем '#{expected}'")
        assert String.contains?(data, expected)

      {:error, reason} ->
        flunk("Таймаут ожидания '#{expected}'. Ошибка: #{reason}")
    end
  end

  defp flush_socket(socket) do
    case :gen_tcp.recv(socket, 0, 10) do
      {:ok, _} -> flush_socket(socket)
      {:error, _} -> :ok
    end
  end
end
