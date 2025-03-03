defmodule Roguelike.GameServer do
  use GenServer
  alias Roguelike.Core
  alias Roguelike.Render

  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    Logger.info("Starting GameServer")
    map_data = Roguelike.GameMap.generate_map()
    state = Core.init(map_data)
    Logger.debug("Initial State Explored: #{inspect(state.explored)}")
    server_pid = self()
    Logger.debug("Server PID (game_server::init): #{inspect(server_pid)}")
    render(state)
    spawn_link(fn -> input_loop(server_pid) end)
    {:ok, state}
  end

  def handle_info({:input, ""}, state) do
    Logger.debug("Received empty input, ignoring")
    render(state)
    {:noreply, state}
  end

  def handle_info({:input, "q"}, state) do
    case state.mode do
      :dead ->
        Logger.info("Quitting game after death")
        # Stop only on "q" in :dead mode
        {:stop, :normal, state}

      _ ->
        Logger.info("Quitting game")
        new_state = %{state | mode: :dead}
        render(new_state)
        # Regular "q" sets :dead, waits for next input
        {:noreply, new_state}
    end
  end

  def handle_info({:input, input}, state) do
    Logger.debug(
      "Received input: #{inspect(input)}, Current State Explored: #{inspect(state.explored)}"
    )

    new_state =
      if state.mode == :dead do
        # Ignore inputs except "q" in :dead mode
        state
      else
        Core.update(state, {:event, %{key: String.to_charlist(input) |> hd}})
      end

    Logger.debug("New State Explored: #{inspect(new_state.explored)}")
    render(new_state)
    {:noreply, new_state}
  end

  def handle_info(msg, state) do
    Logger.warning("Unexpected message: #{inspect(msg)}")
    render(state)
    {:noreply, state}
  end

  defp input_loop(server_pid) do
    input = IO.gets("") |> String.trim()
    Logger.debug("Sending input to server: #{input}")
    Logger.debug("Server PID (game_server::input_loop()): #{inspect(server_pid)}")
    send(server_pid, {:input, input})

    # Continue looping even after "q" until server stops
    input_loop(server_pid)
  end

  defp render(state) do
    IO.write("\e[2J\e[H")
    lines = Render.render_game(state)

    Enum.each(lines, fn line ->
      IO.puts(line.content)
    end)

    IO.write("")
  end
end
