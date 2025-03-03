defmodule Roguelike.Items do
  alias Roguelike.Combat
  alias Roguelike.Entities
  alias Roguelike.GameMap

  @enemy_types Combat.enemy_types()
  @weapon_types Combat.weapon_types()
  @potion_types %{
    "Health Potion" => %{hp_restore: {5, 10}, symbol: "h"},
    "Damage Potion" => %{damage_mult: 1.5, symbol: "D", duration: 10},
    "Defense Potion" => %{defense_mult: 0.5, symbol: "F", duration: 10}
  }

  def spawn_initial_enemies(rooms, player_pos) do
    exclude = player_pos
    initial_enemies = ["Goblin", "Orc", "Troll", "Dragon", "Skeleton"]

    Enum.map(initial_enemies, fn enemy_type ->
      stats = @enemy_types[enemy_type]
      {min_hp, max_hp} = stats.hp_range
      hp = Enum.random(min_hp..max_hp)
      pos = GameMap.place_entity_in_room(rooms, exclude)

      %Entities.Entity{
        pos: pos,
        hp: hp,
        max_hp: hp,
        symbol: stats.symbol,
        damage_range: stats.damage_range,
        xp_value: stats.xp
      }
    end)
  end

  def spawn_items(rooms, player_pos) do
    exclude = player_pos
    initial_weapons = ["Dagger", "Sword", "Axe", "Mace", "Spear", "Bow", "Flaming Sword"]

    weapons =
      Enum.map(initial_weapons, fn weapon_name -> spawn_weapon(weapon_name, rooms, exclude, 0) end)

    potions =
      Enum.map(@potion_types, fn {potion_name, stats} ->
        spawn_potion(potion_name, stats, rooms, exclude, 0)
      end)

    weapons ++ potions
  end

  defp spawn_weapon(name, rooms, exclude, spawn_turn) do
    stats = @weapon_types[name]
    pos = GameMap.place_entity_in_room(rooms, exclude)

    %Entities.Item{
      pos: pos,
      name: name,
      symbol: stats.symbol,
      spawn_turn: spawn_turn,
      despawn_turn: spawn_turn + Enum.random(20..30),
      damage_range: stats.damage_range,
      dot: stats[:dot],
      area_effect: stats[:area_effect],
      life_drain: stats[:life_drain]
    }
  end

  defp spawn_potion(name, stats, rooms, exclude, spawn_turn) do
    pos = GameMap.place_entity_in_room(rooms, exclude)

    %Entities.Item{
      pos: pos,
      name: name,
      symbol: stats.symbol,
      spawn_turn: spawn_turn,
      despawn_turn: spawn_turn + Enum.random(20..30),
      hp_restore: stats[:hp_restore],
      damage_mult: stats[:damage_mult],
      defense_mult: stats[:defense_mult],
      duration: stats[:duration]
    }
  end

  def spawn_random_enemy(rooms, player_pos, player_level) do
    available_types =
      Enum.filter(@enemy_types, fn {_, stats} -> stats.min_level <= player_level end)

    {_enemy_type, stats} = Enum.random(available_types)
    {min_hp, max_hp} = stats.hp_range
    hp = Enum.random(min_hp..max_hp)
    pos = GameMap.place_entity_in_room(rooms, player_pos)

    %Entities.Entity{
      pos: pos,
      hp: hp,
      max_hp: hp,
      symbol: stats.symbol,
      damage_range: stats.damage_range,
      xp_value: stats.xp
    }
  end

  def spawn_random_weapon(rooms, player_pos, items) do
    special_weapons =
      Enum.filter(@weapon_types, fn {_, v} -> v[:dot] || v[:area_effect] || v[:life_drain] end)

    regular_weapons =
      Enum.filter(@weapon_types, fn {k, _} -> k not in Enum.map(special_weapons, &elem(&1, 0)) end)

    has_special =
      Enum.any?(items, fn i ->
        i.damage_range != nil and i.name in Enum.map(special_weapons, &elem(&1, 0))
      end)

    weapon_name =
      if not has_special or :rand.uniform() < 0.2,
        do: Enum.random(special_weapons) |> elem(0),
        else: Enum.random(regular_weapons) |> elem(0)

    spawn_weapon(weapon_name, rooms, player_pos, items |> hd() |> Map.get(:spawn_turn))
  end

  def enemy_name(symbol) do
    Enum.find_value(@enemy_types, fn {k, v} -> if v.symbol == symbol, do: k end)
  end

  def pickup_item(state, new_pos) do
    {picked_items, remaining_items} =
      Enum.split_with(state.items, fn item -> item.pos == new_pos end)

    Enum.reduce(picked_items, %{state | items: remaining_items}, &process_item/2)
  end

  defp process_item(item, state) do
    if item.hp_restore || item.damage_mult || item.defense_mult do
      handle_potion_pickup(state, item)
    else
      handle_weapon_pickup(state, item)
    end
  end

  defp handle_potion_pickup(state, item) do
    new_potions = [item | state.inventory.potions]
    message = "Picked up #{item.name}! Added to inventory. Potions: #{length(new_potions)}"

    %{
      state
      | inventory: %{state.inventory | potions: new_potions},
        user_messages: [message | state.user_messages]
    }
  end

  defp handle_weapon_pickup(state, item) do
    state = if state.inventory.weapon, do: drop_current_weapon(state), else: state
    new_player = %{state.player | damage_range: item.damage_range}
    message = "Picked up #{item.name}! Damage range now #{inspect(item.damage_range)}."

    %{
      state
      | player: new_player,
        inventory: %{state.inventory | weapon: item.name},
        current_weapon_effects: %{
          dot: item.dot,
          area_effect: item.area_effect,
          life_drain: item.life_drain
        },
        user_messages: [message | state.user_messages]
    }
  end

  defp drop_current_weapon(state) do
    {old_weapon_name, old_weapon_stats} =
      Enum.find(@weapon_types, fn {_, v} -> v.damage_range == state.player.damage_range end)

    new_items = [
      %Entities.Item{
        pos: state.player.pos,
        name: old_weapon_name,
        symbol: old_weapon_stats.symbol,
        spawn_turn: state.turn_count,
        despawn_turn: state.turn_count + Enum.random(20..30),
        damage_range: old_weapon_stats.damage_range
      }
      | state.items
    ]

    %{
      state
      | items: new_items,
        user_messages: ["Dropped #{old_weapon_name}." | state.user_messages]
    }
  end

  def apply_potion_effect(state, potion, new_potions) do
    case potion do
      %{hp_restore: {min, max}} ->
        heal = Enum.random(min..max)
        new_player = %{state.player | hp: min(state.player.max_hp, state.player.hp + heal)}

        %{
          state
          | player: new_player,
            inventory: %{state.inventory | potions: new_potions},
            user_messages: [
              "Used #{potion.name}! Restored #{heal} HP. (#{new_player.hp}/#{new_player.max_hp})"
              | state.user_messages
            ]
        }

      %{damage_mult: mult, duration: dur} ->
        new_effects = Map.merge(state.effects, %{damage_mult: mult, turns_left: dur})

        %{
          state
          | effects: new_effects,
            inventory: %{state.inventory | potions: new_potions},
            user_messages: [
              "Used #{potion.name}! Damage increased to x#{mult} for #{dur} turns."
              | state.user_messages
            ]
        }

      %{defense_mult: mult, duration: dur} ->
        new_effects = Map.merge(state.effects, %{defense_mult: mult, turns_left: dur})

        %{
          state
          | effects: new_effects,
            inventory: %{state.inventory | potions: new_potions},
            user_messages: [
              "Used #{potion.name}! Damage reduced to x#{mult} for #{dur} turns."
              | state.user_messages
            ]
        }
    end
  end

  def inspect_inventory(state) do
    weapon = state.inventory.weapon || "None"

    messages = [
      "\nInventory: Equipped Weapon - #{weapon} (Damage: #{inspect(state.player.damage_range)})"
    ]

    messages = append_weapon_effects(messages, state.current_weapon_effects)
    messages = append_potion_list(messages, state.inventory.potions)
    %{state | user_messages: Enum.reverse(messages) ++ state.user_messages}
  end

  defp append_weapon_effects(messages, effects) do
    messages =
      if effects[:dot],
        do: [
          "  Special: #{String.capitalize(effects.dot.type)} DoT (#{inspect(effects.dot.damage)} dmg for #{effects.dot.duration} turns)"
          | messages
        ],
        else: messages

    messages = if effects[:area_effect], do: ["  Special: Area Effect" | messages], else: messages

    if effects[:life_drain],
      do: ["  Special: Life Drain (#{round(effects.life_drain * 100)}% of damage)" | messages],
      else: messages
  end

  defp append_potion_list(messages, potions) do
    messages = ["Potions:" | messages]

    if Enum.empty?(potions),
      do: ["  None" | messages],
      else:
        Enum.reduce(potions, messages, fn potion, acc ->
          ["  - #{potion.name} (#{potion_effect(potion)})" | acc]
        end)
  end

  defp potion_effect(potion) do
    cond do
      potion.hp_restore -> "Heals #{inspect(potion.hp_restore)}"
      potion.damage_mult -> "Dmg x#{potion.damage_mult} for #{potion.duration} turns"
      potion.defense_mult -> "Def x#{potion.defense_mult} for #{potion.duration} turns"
    end
  end
end
