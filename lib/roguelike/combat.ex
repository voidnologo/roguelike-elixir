defmodule Roguelike.Combat do
  alias Roguelike.Entities

  require Logger

  @enemy_types %{
    "Goblin" => %{hp_range: {5, 10}, damage_range: {1, 2}, symbol: "G", min_level: 1, xp: 20},
    "Orc" => %{hp_range: {10, 15}, damage_range: {2, 4}, symbol: "O", min_level: 1, xp: 30},
    "Troll" => %{hp_range: {15, 20}, damage_range: {3, 6}, symbol: "T", min_level: 1, xp: 50},
    "Wraith" => %{hp_range: {20, 25}, damage_range: {4, 7}, symbol: "W", min_level: 3, xp: 70},
    "Dragon" => %{hp_range: {30, 40}, damage_range: {6, 10}, symbol: "D", min_level: 5, xp: 100},
    "Skeleton" => %{hp_range: {5, 8}, damage_range: {1, 3}, symbol: "S", min_level: 1, xp: 15},
    "Kobold" => %{hp_range: {8, 12}, damage_range: {2, 3}, symbol: "K", min_level: 1, xp: 25},
    "Giant Rat" => %{hp_range: {6, 10}, damage_range: {1, 4}, symbol: "R", min_level: 1, xp: 20},
    "Harpy" => %{hp_range: {12, 18}, damage_range: {3, 5}, symbol: "H", min_level: 2, xp: 40},
    "Minotaur" => %{hp_range: {18, 25}, damage_range: {4, 6}, symbol: "M", min_level: 3, xp: 60},
    "Basilisk" => %{hp_range: {20, 30}, damage_range: {5, 8}, symbol: "B", min_level: 4, xp: 80},
    "Chimera" => %{hp_range: {25, 35}, damage_range: {5, 9}, symbol: "C", min_level: 5, xp: 90},
    "Vampire" => %{hp_range: {30, 40}, damage_range: {6, 10}, symbol: "V", min_level: 6, xp: 120},
    "Lich" => %{hp_range: {35, 45}, damage_range: {7, 11}, symbol: "L", min_level: 7, xp: 150},
    "Beholder" => %{hp_range: {40, 60}, damage_range: {8, 12}, symbol: "E", min_level: 8, xp: 200}
  }

  @weapon_types %{
    "Dagger" => %{damage_range: {1, 3}, symbol: "d"},
    "Sword" => %{damage_range: {2, 5}, symbol: "s"},
    "Axe" => %{damage_range: {3, 7}, symbol: "a"},
    "Mace" => %{damage_range: {2, 6}, symbol: "m"},
    "Spear" => %{damage_range: {3, 5}, symbol: "p"},
    "Bow" => %{damage_range: {2, 7}, symbol: "b"},
    "Flaming Sword" => %{
      damage_range: {3, 6},
      symbol: "f",
      dot: %{type: "fire", damage: {1, 3}, duration: 3}
    },
    "Poison Dagger" => %{
      damage_range: {2, 4},
      symbol: "q",
      dot: %{type: "poison", damage: {1, 2}, duration: 3}
    },
    "Explosive Axe" => %{damage_range: {4, 8}, symbol: "x", area_effect: true},
    "Vampiric Mace" => %{damage_range: {3, 7}, symbol: "v", life_drain: 0.25}
  }

  def combat(state, attacker, defender) do
    state
    |> calculate_damage(attacker, defender)
    |> apply_damage(attacker, defender)
    |> apply_weapon_effects(attacker, defender)
    |> (fn {state, _, reduced_damage} -> update_combat_stats(state, attacker, reduced_damage) end).()
    |> handle_combat_outcome(attacker, defender)
  end

  defp calculate_damage(state, attacker, _defender) do
    damage_mult = state.effects.damage_mult || 1.0
    damage = round(Entities.Entity.get_damage(attacker.damage_range) * damage_mult)
    {state, damage}
  end

  defp apply_damage({state, damage}, attacker, defender) do
    defense_mult = if defender == state.player, do: state.effects.defense_mult || 1.0, else: 1.0
    reduced_damage = round(damage * defense_mult)
    new_defender = Entities.Entity.take_damage(defender, reduced_damage)

    message =
      "#{attacker.symbol} deals #{reduced_damage} damage to #{defender.symbol}! (#{new_defender.hp}/#{new_defender.max_hp} HP left)"

    new_state =
      if defender == state.player,
        do: %{state | player: new_defender},
        else: %{
          state
          | enemies:
              Enum.map(state.enemies, fn e -> if e == defender, do: new_defender, else: e end)
        }

    new_state =
      if attacker == state.player or defender == state.player do
        Logger.debug("Combat message added: #{message}")
        %{new_state | user_messages: [message | new_state.user_messages]}
      else
        new_state
      end

    {new_state, new_defender, reduced_damage}
  end

  defp apply_weapon_effects({state, new_defender, reduced_damage}, attacker, defender) do
    if attacker == state.player and state.inventory.weapon != nil do
      weapon_stats = @weapon_types[state.inventory.weapon]

      new_state =
        state
        |> apply_dot_effect(new_defender, defender, weapon_stats)
        |> apply_area_effect(new_defender, reduced_damage, weapon_stats)
        |> apply_life_drain(reduced_damage, weapon_stats)

      # Return tuple even when weapon effects apply
      {new_state, new_defender, reduced_damage}
    else
      # Return tuple when no weapon
      {state, new_defender, reduced_damage}
    end
  end

  defp apply_dot_effect(state, new_defender, defender, weapon_stats) do
    if weapon_stats[:dot] != nil and Entities.Entity.is_alive?(new_defender) do
      dot = weapon_stats[:dot]
      {min_dmg, max_dmg} = dot.damage

      new_defender = %{
        new_defender
        | dot_effect: %{
            type: dot.type,
            damage: Enum.random(min_dmg..max_dmg),
            turns_left: dot.duration
          }
      }

      new_enemies =
        Enum.map(state.enemies, fn e -> if e == defender, do: new_defender, else: e end)

      %{
        state
        | enemies: new_enemies,
          user_messages: [
            "#{new_defender.symbol} is now affected by #{dot.type}!" | state.user_messages
          ]
      }
    else
      state
    end
  end

  defp apply_area_effect(state, new_defender, reduced_damage, weapon_stats) do
    if weapon_stats[:area_effect] != nil and Entities.Entity.is_alive?(new_defender) do
      {enemies, area_messages} =
        Enum.map_reduce(state.enemies, [], fn e, acc ->
          if e != new_defender and Entities.Entity.is_alive?(e) and
               Entities.Position.distance_to(e.pos, new_defender.pos) <= 1 do
            area_damage = div(reduced_damage, 2)
            new_e = Entities.Entity.take_damage(e, area_damage)

            {new_e,
             [
               "#{e.symbol} takes #{area_damage} area damage! (#{new_e.hp}/#{new_e.max_hp} HP left)"
               | acc
             ]}
          else
            {e, acc}
          end
        end)

      %{
        state
        | enemies: enemies,
          user_messages: Enum.reverse(area_messages) ++ state.user_messages
      }
    else
      state
    end
  end

  defp apply_life_drain(state, reduced_damage, weapon_stats) do
    if weapon_stats[:life_drain] != nil do
      heal = round(reduced_damage * weapon_stats.life_drain)
      new_player = %{state.player | hp: min(state.player.max_hp, state.player.hp + heal)}

      %{
        state
        | player: new_player,
          user_messages: [
            "@ drains #{heal} HP! (#{new_player.hp}/#{new_player.max_hp} HP)"
            | state.user_messages
          ]
      }
    else
      state
    end
  end

  defp update_combat_stats(state, attacker, reduced_damage) do
    if attacker == state.player,
      do: %{state | total_damage: state.total_damage + reduced_damage},
      else: state
  end

  defp handle_combat_outcome(state, attacker, defender) do
    if not Entities.Entity.is_alive?(defender) do
      if defender == state.player do
        %{state | mode: :dead, user_messages: ["You Died!" | state.user_messages]}
      else
        handle_enemy_death(state, attacker, defender)
      end
    else
      state
    end
  end

  defp handle_enemy_death(state, attacker, defender) do
    new_xp = state.player_xp + defender.xp_value
    new_kills = state.kills + 1

    new_messages = [
      "#{attacker.symbol} has slain #{defender.symbol}!",
      "Gained #{defender.xp_value} XP! Total XP: #{new_xp}"
      | state.user_messages
    ]

    new_state = %{state | player_xp: new_xp, kills: new_kills, user_messages: new_messages}
    check_level_up(new_state)
  end

  def check_level_up(state) do
    new_level = div(state.player_xp, 100) + 1

    if new_level > state.player_level do
      new_max_hp = state.player.max_hp + 5
      {min_dmg, max_dmg} = state.player.damage_range
      new_damage_range = {min_dmg + 1, max_dmg + 1}

      message =
        "Level Up! Reached Level #{new_level} - HP: #{new_max_hp}, Damage: #{inspect(new_damage_range)}"

      %{
        state
        | player_level: new_level,
          player: %{
            state.player
            | max_hp: new_max_hp,
              hp: new_max_hp,
              damage_range: new_damage_range
          },
          user_messages: [message | state.user_messages]
      }
    else
      state
    end
  end

  def enemy_types, do: @enemy_types
  def weapon_types, do: @weapon_types
end
