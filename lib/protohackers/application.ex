defmodule Protohackers.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    IO.puts("Starting in #{Mix.env()} environment")

    # children = [
    #   {Registry, keys: :duplicate, name: Protohackers.ChatRegistry}
    # ]
    #
    # servers =
    #   if Mix.env() == :test do
    #     []
    #   else
    #     [
    #       # Starts a worker by calling: Protohackers.Worker.start_link(arg)
    #       # {Protohackers.Worker, arg}
    #       {Protohackers.EchoServer, []},
    #       {Protohackers.PrimeServer, [5002]},
    #       {Protohackers.PriceServer, [port: 5003]},
    #       {Protohackers.ChatServer, [port: 5004]}
    #     ]
    #   end

    children = [
      {Protohackers.EchoServer, port: 5001},
      {Protohackers.PrimeServer, port: 5002},
      {Protohackers.PriceServer, port: 5003},
      {Protohackers.BudgetChatServer, port: 5004}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Protohackers.Supervisor]
    # Supervisor.start_link(children ++ servers, opts)
    Supervisor.start_link(children, opts)
  end
end
