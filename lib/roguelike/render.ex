defmodule Roguelike.Render do
  alias Roguelike.Combat
  alias Roguelike.Entities
  alias Roguelike.Map

  @reset "\e[0m"
  @red "\e[31m"
  @cyan "\e[36m"
  @magenta "\e[35m"
  @green "\e[32m"
  @yellow "\e[33m"
  @gray "\e[90m"
  @enemy_symbols Enum.map(Combat.enemy_types(), fn {_, stats} -> stats.symbol end)
  @weapon_symbols Enum.map(Combat.weapon_types(), fn {_, stats} -> stats.symbol end)

  def render_game(state) do
    render_map = render_items(state) |> render_enemies(state)
    map_lines = build_map_lines(state, render_map)

    case state.mode do
      :game -> render_game_mode(state, map_lines)
      :dead -> render_dead_mode(state, map_lines)
      :inventory -> render_inventory_mode(state, map_lines)
      :potion_menu -> render_potion_menu(state, map_lines)
    end
  end

  defp render_items(state) do
    Enum.reduce(state.items, state.map, fn item, acc ->
      if Map.is_visible?(state.player.pos, item.pos, acc),
        do: Map.put_in_map(acc, item.pos.y, item.pos.x, item.symbol),
        else: acc
    end)
  end

  defp render_enemies(render_map, state) do
    Enum.reduce(state.enemies, render_map, fn enemy, acc ->
      if Entities.Entity.is_alive?(enemy) and Map.is_visible?(state.player.pos, enemy.pos, acc),
        do: Map.put_in_map(acc, enemy.pos.y, enemy.pos.x, enemy.symbol),
        else: acc
    end)
  end

  defp build_map_lines(state, render_map) do
    for y <- 0..19 do
      row =
        for x <- 0..39, into: "" do
          pos = %Entities.Position{x: x, y: y}
          base_tile = state.map[y][x]
          render_tile = render_map[y][x]
          render_tile(pos, base_tile, render_tile, state)
        end

      %{content: row}
    end
  end

  defp render_tile(pos, base_tile, render_tile, state) do
    cond do
      pos == state.player.pos ->
        "#{@yellow}@#{@reset}"

      Map.is_visible?(state.player.pos, pos, state.map) ->
        render_visible_tile(render_tile)

      MapSet.member?(state.explored, {x, y}) ->
        render_explored_tile(base_tile)

      true ->
        " "
    end
  end

  defp render_visible_tile(tile) do
    cond do
      tile in @enemy_symbols ->
        "#{@red}#{tile}#{@reset}"

      tile in @weapon_symbols ->
        if Enum.any?(Combat.weapon_types(), fn {_, v} ->
             v.symbol == tile and (v[:dot] || v[:area_effect] || v[:life_drain])
           end),
           do: "#{@magenta}#{tile}#{@reset}",
           else: "#{@cyan}#{tile}#{@reset}"

      tile in ["h", "D", "F"] ->
        "#{@green}#{tile}#{@reset}"

      tile == "#" ->
        "#{@gray}##{@reset}"

      true ->
        tile
    end
  end

  defp render_explored_tile(tile) do
    case tile do
      "#" -> "#{@gray}##{@reset}"
      "." -> "."
      "+" -> "+"
      "/" -> "/"
      _ -> " "
    end
  end

  defp render_game_mode(state, map_lines) do
    user_lines = Enum.map(Enum.take(state.user_messages, 5), fn msg -> %{content: msg} end)
    state_lines = Enum.map(Enum.take(state.state_messages, 5), fn msg -> %{content: msg} end)
    immediate_lines = build_game_status(state)

    map_lines ++
      user_lines ++ [%{content: "----"}] ++ state_lines ++ [%{content: "----"}] ++ immediate_lines
  end

  defp build_game_status(state) do
    enemy_hp = build_enemy_hp(state.enemies)
    effects_str = build_effects_str(state.effects)
    legend = build_legend(state)

    [
      %{
        content:
          "Player: Level #{state.player_level} (XP: #{state.player_xp}) HP: #{state.player.hp}/#{state.player.max_hp}  Enemies: #{enemy_hp || "None"}"
      },
      %{content: "Potions: #{length(state.inventory.potions)}  #{effects_str}"},
      %{
        content:
          "Next spawn in #{state.next_spawn_turn - state.turn_count} turns  Next weapon spawn in #{state.next_weapon_spawn_turn - state.turn_count} turns"
      },
      %{content: "Controls: WASD to move, I to inspect, U to use potion, Q to quit"},
      %{content: legend}
    ]
  end

  defp build_enemy_hp(enemies) do
    Enum.map_join(Enum.filter(enemies, &Entities.Entity.is_alive?/1), " | ", fn e ->
      "#{@red}#{e.symbol}#{@reset}: #{e.hp}/#{e.max_hp}"
    end)
  end

  defp build_effects_str(effects) do
    if effects.turns_left > 0,
      do:
        "Effects: Dmg x#{effects.damage_mult || 1.0}, Def x#{effects.defense_mult || 1.0} (#{effects.turns_left} turns)",
      else: "Effects: None"
  end

  defp build_legend(state) do
    visible_entities =
      Enum.filter(state.items ++ state.enemies, fn entity ->
        Map.is_visible?(state.player.pos, entity.pos, state.map) and
          (match?(%Entities.Item{}, entity) or Entities.Entity.is_alive?(entity))
      end)

    symbol_meanings =
      Enum.map(visible_entities, fn entity ->
        symbol = entity.symbol

        cond do
          symbol in @enemy_symbols ->
            name =
              Enum.find_value(Combat.enemy_types(), fn {k, v} -> if v.symbol == symbol, do: k end)

            "#{@red}#{symbol}#{@reset}=#{name}"

          symbol in @weapon_symbols ->
            name =
              Enum.find_value(Combat.weapon_types(), fn {k, v} -> if v.symbol == symbol, do: k end)

            color =
              if Enum.any?(Combat.weapon_types(), fn {_, v} ->
                   v.symbol == symbol and (v[:dot] || v[:area_effect] || v[:life_drain])
                 end),
                 do: @magenta,
                 else: @cyan

            "#{color}#{symbol}#{@reset}=#{name}"

          symbol in ["h", "D", "F"] ->
            name =
              Enum.find_value(
                %{"h" => "Health Potion", "D" => "Damage Potion", "F" => "Defense Potion"},
                fn {k, v} -> if k == symbol, do: v end
              )

            "#{@green}#{symbol}#{@reset}=#{name}"

          true ->
            nil
        end
      end)
      |> Enum.filter(& &1)
      |> Enum.uniq()

    "Symbols: " <>
      if(symbol_meanings != [], do: Enum.join(symbol_meanings, ", "), else: "None visible")
  end

  defp render_dead_mode(state, map_lines) do
    end_screen_lines = [
      %{content: "You Died!"},
      %{content: "Final Stats:"},
      %{content: "Kills: #{state.kills}"},
      %{content: "Total Damage Dealt: #{state.total_damage}"},
      %{content: "XP Earned: #{state.player_xp}"},
      %{content: "Level Reached: #{state.player_level}"},
      %{content: "Turns Survived: #{state.turn_count}"},
      %{content: "Press Q to quit"}
    ]

    map_lines ++ end_screen_lines
  end

  defp render_inventory_mode(state, map_lines) do
    user_lines = Enum.map(Enum.take(state.user_messages, 5), fn msg -> %{content: msg} end)
    immediate_lines = [%{content: "Press I to return to game"}]
    map_lines ++ user_lines ++ [%{content: "----"}] ++ immediate_lines
  end

  defp render_potion_menu(state, map_lines) do
    potion_lines =
      Enum.with_index(state.inventory.potions, 1)
      |> Enum.map(fn {potion, i} ->
        effect =
          cond do
            potion.hp_restore ->
              "Heals #{inspect(potion.hp_restore)}"

            potion.damage_mult ->
              "Increases damage to x#{potion.damage_mult} for #{potion.duration} turns"

            potion.defense_mult ->
              "Reduces damage to x#{potion.defense_mult} for #{potion.duration} turns"
          end

        %{content: "#{i}. #{potion.name} (#{effect})"}
      end)

    status_lines = build_potion_menu_status(state)

    ([%{content: "Use Potion (Select 1-#{length(state.inventory.potions)} or U/Q to cancel)"}] ++
       potion_lines ++ status_lines)
    |> Enum.concat(map_lines)
  end

  defp build_potion_menu_status(state) do
    enemy_hp = build_enemy_hp(state.enemies)
    effects_str = build_effects_str(state.effects)
    legend = build_legend(state)

    Enum.reverse([
      %{
        content:
          "Player: Level #{state.player_level} (XP: #{state.player_xp}) HP: #{state.player.hp}/#{state.player.max_hp}  Enemies: #{enemy_hp || "None"}"
      },
      %{content: "Potions: #{length(state.inventory.potions)}  #{effects_str}"},
      %{
        content:
          "Next spawn in #{state.next_spawn_turn - state.turn_count} turns  Next weapon spawn in #{state.next_weapon_spawn_turn - state.turn_count} turns"
      },
      %{content: legend}
    ])
  end
end
