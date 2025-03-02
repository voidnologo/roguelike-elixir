defmodule Roguelike.GameServer do
  use GenServer

  require Logger

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    Logger.configure(level: :debug)
    Logger.debug("Logger level set to debug")
    Logger.info("Initializing GameServer")
    IO.write("\e[2J\e[H")
    map_data = Roguelike.generate_map()
    state = Roguelike.init(map_data)
    Roguelike.render_game(state)
    Process.send_after(self(), :poll_input, 100)
    {:ok, state}
  end

  def handle_info(:poll_input, state) do
    case IO.getn(:stdio, "", 1) do
      "" ->
        Logger.debug("Skipping empty input")
        Process.send_after(self(), :poll_input, 100)
        {:noreply, state}

      "\n" ->
        Logger.debug("Skipping newline input")
        Process.send_after(self(), :poll_input, 100)
        {:noreply, state}

      ch when ch in ["q", "Q"] ->
        IO.write("\e[2J\e[H")
        {:stop, :normal, state}

      ch when ch in ["w", "s", "a", "d"] ->
        msg = {:event, %{key: String.to_charlist(ch) |> hd}}
        Logger.debug("Before update: #{inspect(state)}")
        new_state = Roguelike.update(state, msg)
        Logger.debug("State after update: #{inspect(new_state)}")
        Roguelike.render_game(new_state)
        Process.send_after(self(), :poll_input, 100)
        {:noreply, new_state}

      ch when ch in ["i", "u"] ->
        msg = {:event, %{ch: String.to_charlist(ch) |> hd}}
        Logger.debug("Before update: #{inspect(state)}")
        new_state = Roguelike.update(state, msg)
        Logger.debug("State after update: #{inspect(new_state)}")
        Roguelike.render_game(new_state)
        Process.send_after(self(), :poll_input, 100)
        {:noreply, new_state}

      ch when ch in ["1", "2", "3", "4", "5", "6", "7", "8", "9"] ->
        msg = {:event, %{ch: String.to_charlist(ch) |> hd}}
        Logger.debug("Numeric input detected: #{ch}")
        new_state = Roguelike.update(state, msg)
        Roguelike.render_game(new_state)
        Process.send_after(self(), :poll_input, 100)
        {:noreply, new_state}

      ch ->
        msg = {:event, %{ch: String.to_charlist(ch) |> hd}}
        Logger.debug("Other input detected: #{ch}")
        new_state = Roguelike.update(state, msg)
        Roguelike.render_game(new_state)
        Process.send_after(self(), :poll_input, 100)
        {:noreply, new_state}
    end
  end
end
