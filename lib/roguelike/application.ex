defmodule Roguelike.Application do
  use Application

  require Logger

  def start(_type, _args) do
    Logger.info("Starting Roguelike application")

    children = [
      {Roguelike.GameServer, []}
    ]

    opts = [strategy: :one_for_one, name: Roguelike.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
