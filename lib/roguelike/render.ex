defmodule Roguelike.Render do
  alias Roguelike.GameMap
  alias Roguelike.Entities
  alias Roguelike.Combat
  alias Roguelike.Items
  require Logger

  @black IO.ANSI.black()
  @white IO.ANSI.white()
  @bright IO.ANSI.bright()
  @cyan IO.ANSI.cyan()
  @magenta IO.ANSI.magenta()
  @green IO.ANSI.green()
  @yellow IO.ANSI.yellow()
  @red IO.ANSI.red()
  @reset IO.ANSI.reset()

  def render_game(state) do
    Logger.debug("Render game state: explored #{inspect(state.explored)}")
    lines = Enum.map(0..19, fn y -> render_line(state, y) end)

    case state.mode do
      :game ->
        lines ++ render_messages(state) ++ render_status(state)

      :inventory ->
        lines ++ render_inventory(state.inventory)

      :potion_menu ->
        lines ++ render_potion_menu(state)

      :dead ->
        lines ++ [%{content: "Game Over! Press Q to quit."}]
    end
  end

  defp render_line(state, y) do
    content =
      Enum.reduce(0..39, "", fn x, acc ->
        pos = %Entities.Position{x: x, y: y}
        tile = render_tile(state, pos)
        acc <> tile
      end)

    %{content: content}
  end

  defp render_tile(state, pos) do
    cond do
      state.player.pos == pos ->
        render_player(state)

      enemy = Enum.find(state.enemies, &(&1.pos == pos and Entities.Entity.is_alive?(&1))) ->
        render_enemy(state, enemy)

      item = Enum.find(state.items, &(&1.pos == pos)) ->
        render_item(state, item)

      true ->
        render_map(state, pos)
    end
  end

  defp render_player(state) do
    case state.mode do
      :dead -> @red <> "@" <> @reset
      _ -> @white <> @bright <> "@" <> @reset
    end
  end

  defp render_enemy(state, enemy) do
    if GameMap.is_visible?(state.player.pos, enemy.pos, state.map) do
      @yellow <> enemy.symbol <> @reset
    else
      render_map(state, enemy.pos)
    end
  end

  defp render_item(state, item) do
    if MapSet.member?(state.explored, {item.pos.x, item.pos.y}) and
         GameMap.is_visible?(state.player.pos, item.pos, state.map) do
      case item.damage_range do
        nil ->
          @green <> item.symbol <> @reset

        _ ->
          if item.dot != nil or item.area_effect != nil or item.life_drain != nil,
            do: @magenta <> item.symbol <> @reset,
            else: @cyan <> item.symbol <> @reset
      end
    else
      render_map(state, item.pos)
    end
  end

  defp render_map(state, pos) do
    if MapSet.member?(state.explored, {pos.x, pos.y}) do
      tile = Map.get(state.map[pos.y], pos.x)

      if GameMap.is_visible?(state.player.pos, pos, state.map) do
        case tile do
          "#" -> @white <> "#" <> @reset
          "." -> @white <> "." <> @reset
          "+" -> @yellow <> "+" <> @reset
          "/" -> @yellow <> "/" <> @reset
          _ -> tile
        end
      else
        @black <> tile <> @reset
      end
    else
      " "
    end
  end

  defp render_messages(state) do
    user_messages =
      Enum.map(state.user_messages, fn message ->
        %{content: message}
      end)

    state_messages =
      Enum.map(state.state_messages, fn message ->
        %{content: message}
      end)

    if length(user_messages) + length(state_messages) > 0 do
      [%{content: "----"}] ++ user_messages ++ state_messages ++ [%{content: "----"}]
    else
      []
    end
  end

  defp enemy_hp_string(state) do
    visible_enemies =
      Enum.filter(state.enemies, fn e ->
        Entities.Entity.is_alive?(e) and GameMap.is_visible?(state.player.pos, e.pos, state.map)
      end)

    Enum.map(visible_enemies, fn enemy ->
      "#{enemy.symbol}: #{enemy.hp}/#{enemy.max_hp}"
    end)
    |> Enum.join(" | ")
  end

  defp effects_string(state) do
    if state.effects.turns_left > 0 do
      dmg = if state.effects.damage_mult != 1.0, do: "Dmg x#{state.effects.damage_mult}", else: ""

      defen =
        if state.effects.defense_mult != 1.0, do: "Def x#{state.effects.defense_mult}", else: ""

      [dmg, defen]
      |> Enum.filter(&(&1 != ""))
      |> Enum.join(", ")
      |> Kernel.<>(" (#{state.effects.turns_left}t)")
    else
      "None"
    end
  end

  defp render_status(state) do
    enemy_hp = enemy_hp_string(state)
    effects = effects_string(state)

    symbols =
      Enum.filter(state.items, fn item ->
        MapSet.member?(state.explored, {item.pos.x, item.pos.y}) and
          GameMap.is_visible?(state.player.pos, item.pos, state.map)
      end)
      |> Enum.map(fn item ->
        symbol = item.symbol
        name = item.name
        if String.length(symbol) == 1, do: "#{symbol}=#{name}", else: nil
      end)
      |> Enum.filter(& &1)
      |> Enum.join(" ")

    [
      %{
        content:
          "Player: Level #{state.player_level} (XP: #{state.player_xp}) HP: #{state.player.hp}/#{state.player.max_hp}  Enemies: #{enemy_hp}"
      },
      %{content: "Potions: #{length(state.inventory.potions)}  Effects: #{effects}"},
      %{
        content:
          "Next spawn in #{state.next_spawn_turn - state.turn_count} turns  Next weapon spawn in #{state.next_weapon_spawn_turn - state.turn_count} turns"
      },
      %{content: "Controls: WASD to move, I to inspect, U to use potion, Q to quit"},
      %{content: "Symbols: #{if symbols == "", do: "None visible", else: symbols}"}
    ]
  end

  defp render_inventory(inventory) do
    weapon_string =
      "Equipped Weapon - #{if inventory.weapon, do: inventory.weapon, else: "None"} (Damage: #{if inventory.weapon, do: inspect(Combat.weapon_types()[inventory.weapon].damage_range), else: "nil"})"

    potion_strings =
      if inventory.potions != [] do
        Enum.map(inventory.potions, fn potion ->
          case potion do
            "Health Potion" ->
              "  - Health Potion (Heals #{inspect(Items.potion_types()[potion].hp_restore)})"

            "Damage Potion" ->
              "  - Damage Potion (Increases damage to x#{Items.potion_types()[potion].damage_mult} for #{Items.potion_types()[potion].duration} turns)"

            "Defense Potion" ->
              "  - Defense Potion (Reduces damage to x#{Items.potion_types()[potion].defense_mult} for #{Items.potion_types()[potion].duration} turns)"
          end
        end)
      else
        ["  - None"]
      end

    [
      %{content: "Inventory: #{weapon_string}"},
      %{content: "Potions:"}
    ] ++
      Enum.map(potion_strings, fn potion -> %{content: potion} end) ++
      [%{content: "----"}, %{content: "Press I to return to game"}]
  end

  defp render_potion_menu(state) do
    numbered_potion_list =
      state.inventory.potions
      |> Enum.with_index()
      |> Enum.map(fn {elem, index} ->
        case elem do
          "Health Potion" ->
            "#{index + 1}. Health Potion (Heals #{inspect(Items.potion_types()[elem].hp_restore)})"

          "Damage Potion" ->
            "#{index + 1}. Damage Potion (Increases damage to x#{Items.potion_types()[elem].damage_mult} for #{Items.potion_types()[elem].duration} turns)"

          "Defense Potion" ->
            "#{index + 1}. Defense Potion (Reduces damage to x#{Items.potion_types()[elem].defense_mult} for #{Items.potion_types()[elem].duration} turns)"
        end
      end)

    [
      %{
        content: "Use Potion (Select 1-#{length(state.inventory.potions)} or U/Q to cancel)"
      }
    ] ++
      Enum.map(numbered_potion_list, fn potion -> %{content: potion} end) ++
      render_status(state)
  end
end
