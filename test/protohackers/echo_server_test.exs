defmodule Protohackers.EchoServerTest do
  use ExUnit.Case

  test "echoes anything back" do
    {:ok, socket} = :gen_tcp.connect(~c"localhost", 5001, mode: :binary, active: false)
    assert :gen_tcp.send(socket, "foo") == :ok
    assert :gen_tcp.recv(socket, 3, 5000) == {:ok, "foo"}

    assert :gen_tcp.send(socket, "bar") == :ok
    assert :gen_tcp.recv(socket, 3, 5000) == {:ok, "bar"}
    # :gen_tcp.shutdown(socket, :write)
    # assert :gen_tcp.recv(socket, 0, 5000) == {:ok, "foobar"}
    :gen_tcp.close(socket)
  end

  @tag :capture_log
  test "echo server has a max buffer size" do
    {:ok, socket} = :gen_tcp.connect(~c"localhost", 5001, mode: :binary, active: false)
    limit = 1024 * 100
    payload = :binary.copy("a", limit + 1)

    assert :gen_tcp.send(socket, payload) == :ok

    # Добавляем :timeout в ветки case
    # read_until_closed = fn func ->
    #   case :gen_tcp.recv(socket, 0, 1000) do
    #     {:ok, _data} ->
    #       func.(func)
    #
    #     {:error, :closed} ->
    #       :ok
    #       {:error, :timeout}
    #   end
    # end

    # read_until_closed.(read_until_closed)
    # 2. Вычитываем все данные, которые сервер успел отправить обратно перед закрытием.
    # Stream.repeatedly будет вызывать recv, пока тот возвращает {:ok, ...}
    _received_data =
      Stream.repeatedly(fn -> :gen_tcp.recv(socket, 0, 500) end)
      |> Enum.take_while(&match?({:ok, _}, &1))

    case :gen_tcp.recv(socket, 0, 500) do
      {:error, :closed} -> :ok
      {:error, :enotconn} -> :ok
      other -> flunk("Expected socket to be closed, but got: #{inspect(other)}")
    end

    # Мы ожидаем, что сокет либо закрыт (:closed), 
    # либо соединение уже полностью разорвано (:enotconn)
    assert :gen_tcp.recv(socket, 0, 1000) in [{:error, :closed}, {:error, :enotconn}]
  end

  test "handles multiple concurrent connections" do
    tasks =
      for i <- 1..10 do
        Task.async(fn ->
          {:ok, socket} = :gen_tcp.connect(~c"localhost", 5001, mode: :binary, active: false)
          msg = "message_#{i}"
          len = byte_size(msg)
          assert :gen_tcp.send(socket, msg) == :ok
          assert :gen_tcp.recv(socket, len, 5000) == {:ok, msg}
          # :gen_tcp.shutdown(socket, :write)
          # assert :gen_tcp.recv(socket, 0, 5000) == {:ok, msg}
          :gen_tcp.close(socket)
        end)
      end

    # Enum.each(tasks, &Task.await/1)
    Task.await_many(tasks, 10_000)
  end
end
