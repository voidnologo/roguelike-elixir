defmodule Roguelike do
  alias Roguelike.Core
  alias Roguelike.Map
  alias Roguelike.Render

  defdelegate init(map_data), to: Core
  defdelegate update(state, msg), to: Core
  defdelegate render_game(state), to: Render
  defdelegate generate_map, to: Map
end
