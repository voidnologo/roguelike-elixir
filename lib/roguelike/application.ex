defmodule Roguelike.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Roguelike.GameServer, []}
    ]

    opts = [strategy: :one_for_one, name: Roguelike.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
