defmodule Protohackers.PriceServerTest do
  use ExUnit.Case

  # Порт, на котором будет запущен PriceServer
  @port 5003

  # setup do
  #   # Запускаем сервер перед каждым тестом (если он не запущен глобально)
  #   # Если запущен в application.ex, эту строку можно закомментировать
  #   start_supervised!({Protohackers.PriceServer, @port})
  #   :ok
  # end

  test "inserts and queries prices" do
    {:ok, socket} = :gen_tcp.connect(~c"localhost", @port, mode: :binary, active: false)

    # 1. Вставляем цены (Insert: 'I', timestamp, price)
    # <<?I, 100::signed-32, 25::signed-32>>
    :ok = :gen_tcp.send(socket, <<?I, 100::32, 25::32>>)
    :ok = :gen_tcp.send(socket, <<?I, 101::32, 35::32>>)
    :ok = :gen_tcp.send(socket, <<?I, 102::32, 45::32>>)

    # 2. Запрашиваем среднее (Query: 'Q', mintime, maxtime)
    # Диапазон 100..102 (среднее между 25, 35, 45 должно быть 35)
    :ok = :gen_tcp.send(socket, <<?Q, 100::32, 102::32>>)

    # Ожидаем 4 байта ответа
    assert {:ok, <<35::signed-32>>} == :gen_tcp.recv(socket, 4, 5000)

    # 3. Запрос за пределами диапазона (должен вернуть 0)
    :ok = :gen_tcp.send(socket, <<?Q, 200::32, 300::32>>)
    assert {:ok, <<0::signed-32>>} == :gen_tcp.recv(socket, 4, 5000)

    # :ok = :gen_tcp.send(socket, <<?I, 102::32, -50::signed-32>>)
    # :ok = :gen_tcp.send(socket, <<?Q, 100::32, 100::32>>)
    # assert {:ok, <<-50::signed-32>>} == :gen_tcp.recv(socket, 4, 5000)
    :gen_tcp.close(socket)
  end

  test "handles negative prices correctly" do
    # Открываем НОВОЕ соединение (пустая карта цен на сервере)
    {:ok, socket} = :gen_tcp.connect(~c"localhost", @port, [:binary, active: false])

    # 1. Вставляем только одну отрицательную цену
    :ok = :gen_tcp.send(socket, <<?I, 100::signed-32, -50::signed-32>>)

    # 2. Запрашиваем среднее именно для этого времени
    :ok = :gen_tcp.send(socket, <<?Q, 100::signed-32, 100::signed-32>>)

    # 3. Теперь сервер должен вернуть ровно -50
    assert {:ok, <<-50::signed-32>>} == :gen_tcp.recv(socket, 4, 5000)

    :gen_tcp.close(socket)
  end

  test "handles mean prices correctly" do
    {:ok, socket} = :gen_tcp.connect(~c"localhost", @port, mode: :binary, active: false)
    :ok = :gen_tcp.send(socket, <<?I, 10::32, 10::32>>)

    :ok = :gen_tcp.send(socket, <<?I, 20::32, -50::32>>)
    :ok = :gen_tcp.send(socket, <<?Q, 0::32, 100::32>>)

    # Ожидаем -20
    assert {:ok, <<-20::signed-32>>} == :gen_tcp.recv(socket, 4, 5000)
    :gen_tcp.close(socket)
  end

  test "handles empty range or mintime > maxtime" do
    {:ok, socket} = :gen_tcp.connect(~c"localhost", @port, mode: :binary, active: false)

    # Отправляем запрос, где min > max
    :ok = :gen_tcp.send(socket, <<?Q, 500::32, 400::32>>)
    assert {:ok, <<0::signed-32>>} == :gen_tcp.recv(socket, 4, 5000)

    :gen_tcp.close(socket)
  end
end
