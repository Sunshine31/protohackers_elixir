defmodule Protohackers.PrimeServerTest do
  use ExUnit.Case

  @port 5002
  setup do
    # Запускает сервер только для этого теста и привязывает к его жизненному циклу
    start_supervised!({Protohackers.PrimeServer, 5002})
    :ok
  end

  test "handles a request sent byte by byte" do
    {:ok, socket} = :gen_tcp.connect(~c"localhost", @port, mode: :binary, active: false)

    payload = "{\"method\":\"isPrime\",\"number\":7}\n"

    # Отправляем запрос по одному символу
    for char <- String.codepoints(payload) do
      :ok = :gen_tcp.send(socket, char)

      # Небольшая задержка, чтобы сервер успел вызвать recv
      Process.sleep(10)
    end

    # Ждем ответ
    {:ok, response_data} = :gen_tcp.recv(socket, 0, 5000)

    # Декодируем ответ, чтобы убедиться, что это валидный JSON
    assert {:ok, %{"method" => "isPrime", "prime" => true}} = Jason.decode(response_data)

    :gen_tcp.close(socket)
  end

  test "closes connection on malformed JSON" do
    {:ok, socket} = :gen_tcp.connect(~c"localhost", @port, mode: :binary, active: false)

    # Отправляем некорректный JSON
    assert :gen_tcp.send(socket, "{\"method\":\"isPrime\",\"number\":\"not_a_number\"}\n") == :ok

    # Сервер должен что-то ответить и закрыть сокет
    # Мы ожидаем, что следующий recv вернет :closed (или данные и потом :closed)
    _ = :gen_tcp.recv(socket, 0, 1000)
    assert :gen_tcp.recv(socket, 0, 1000) in [{:error, :closed}, {:error, :enotconn}]
  end

  test "handles multiple requests in one packet" do
    {:ok, socket} = :gen_tcp.connect(~c"localhost", @port, mode: :binary, active: false)

    # Два запроса в одной строке
    req1 = "{\"method\":\"isPrime\",\"number\":2}\n"
    req2 = "{\"method\":\"isPrime\",\"number\":4}\n"

    assert :gen_tcp.send(socket, req1 <> req2) == :ok

    # Читаем ответы. Мы должны получить две строки.
    # Так как мы в active: false, вычитаем их по очереди.
    {:ok, res1} = :gen_tcp.recv(socket, 0, 2000)

    res =
      if String.contains?(res1, "false") do
        res1
      else
        {:ok, res2} = :gen_tcp.recv(socket, 0, 2000)
        res1 <> res2
      end

    # Проверяем, что в ответе есть оба результата
    assert res =~ "\"prime\":true"
    assert res =~ "\"prime\":false"

    :gen_tcp.close(socket)
  end
end
