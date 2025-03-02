defmodule Roguelike.Core do
  alias Roguelike.Combat
  alias Roguelike.Entities
  alias Roguelike.Items
  alias Roguelike.Map

  require Logger

  def init(map_data) do
    player = %Entities.Entity{
      pos: Map.place_entity_in_room(map_data.rooms, nil),
      hp: 20,
      max_hp: 20,
      symbol: "@"
    }

    %{
      map: map_data.map,
      rooms: map_data.rooms,
      player: player,
      enemies: Items.spawn_initial_enemies(map_data.rooms, player.pos),
      items: Items.spawn_items(map_data.rooms, player.pos),
      explored: MapSet.new(),
      player_xp: 0,
      player_level: 1,
      turn_count: 0,
      next_spawn_turn: Enum.random(15..25),
      next_weapon_spawn_turn: Enum.random(15..25),
      inventory: %{weapon: nil, potions: []},
      effects: %{damage_mult: 1.0, defense_mult: 1.0, turns_left: 0},
      current_weapon_effects: %{},
      user_messages: [],
      state_messages: [],
      mode: :game,
      kills: 0,
      total_damage: 0
    }
  end

  def update(state, msg) do
    case state.mode do
      :game -> update_game_mode(state, msg)
      :inventory -> update_inventory_mode(state, msg)
      :potion_menu -> update_potion_menu(state, msg)
      :dead -> update_dead_mode(state, msg)
    end
  end

  defp update_game_mode(state, msg) do
    if not Entities.Entity.is_alive?(state.player) do
      %{state | mode: :dead, user_messages: ["You Died!" | state.user_messages]}
    else
      handle_game_input(state, msg)
    end
  end

  defp handle_game_input(state, {:event, %{ch: ?q}}) do
    %{state | running: false}
  end

  defp handle_game_input(state, {:event, %{ch: ?i}}) when state.player.hp > 0 do
    new_state = Items.inspect_inventory(state)
    %{new_state | mode: :inventory}
  end

  defp handle_game_input(state, {:event, %{ch: ?u}}) when state.player.hp > 0 do
    %{state | mode: :potion_menu}
  end

  defp handle_game_input(state, {:event, %{key: key}})
       when key in [?w, ?s, ?a, ?d] and state.player.hp > 0 do
    {dx, dy} = movement_delta(key)
    move_player(state, dx, dy)
  end

  defp handle_game_input(state, _msg), do: update_explored_and_effects(state)

  defp movement_delta(?w), do: {0, -1}
  defp movement_delta(?s), do: {0, 1}
  defp movement_delta(?a), do: {-1, 0}
  defp movement_delta(?d), do: {1, 0}

  defp move_player(state, dx, dy) do
    old_pos = state.player.pos
    new_pos = Entities.Position.move(old_pos, dx, dy)
    Logger.debug("Attempting move from #{inspect(old_pos)} to #{inspect(new_pos)}")

    if Map.is_valid_move?(new_pos, state.map) do
      handle_valid_move(state, old_pos, new_pos)
    else
      Logger.debug(
        "Move blocked at #{inspect(new_pos)}: #{Map.get(state.map[new_pos.y], new_pos.x, "#")}"
      )

      update_explored_and_effects(state)
    end
  end

  defp handle_valid_move(state, old_pos, new_pos) do
    enemy_at_new_pos =
      Enum.find(state.enemies, fn e -> e.pos == new_pos and Entities.Entity.is_alive?(e) end)

    new_state = update_explored(state)

    if enemy_at_new_pos do
      Logger.debug("Attacking enemy #{enemy_at_new_pos.symbol} at #{inspect(new_pos)}")

      Combat.combat(new_state, new_state.player, enemy_at_new_pos)
      |> update_effects()
    else
      process_tile(state, old_pos, new_pos)
    end
  end

  defp process_tile(state, old_pos, new_pos) do
    new_map = Map.put_in_map(state.map, old_pos.y, old_pos.x, ".")
    Logger.debug("Old position cleared: #{inspect({old_pos.x, old_pos.y})} set to '.'")
    tile = state.map[new_pos.y][new_pos.x]

    case tile do
      "+" ->
        new_map = Map.put_in_map(new_map, new_pos.y, new_pos.x, "/")
        update_effects(%{state | map: new_map})

      "/" ->
        new_player = %{state.player | pos: new_pos}
        new_state = %{state | map: new_map, player: new_player}
        Items.pickup_item(new_state, new_pos) |> update_effects()

      "." ->
        new_player = %{state.player | pos: new_pos}
        new_state = %{state | map: new_map, player: new_player}
        Items.pickup_item(new_state, new_pos) |> update_effects()

      _ ->
        new_player = %{state.player | pos: new_pos}
        new_state = %{state | map: new_map, player: new_player}
        Items.pickup_item(new_state, new_pos) |> update_effects()
    end
  end

  defp update_inventory_mode(state, {:event, %{ch: ?i}}) do
    Logger.debug("Exiting inventory mode")
    %{state | mode: :game, user_messages: []}
  end

  defp update_inventory_mode(state, _msg) do
    Logger.debug("Ignoring input in inventory mode: #{inspect(msg)}")
    state
  end

  defp update_potion_menu(state, {:event, %{ch: ch}}) when ch in ?1..?9 do
    apply_potion(state, ch)
  end

  defp update_potion_menu(state, {:event, %{ch: ch}}) when ch in [?u, ?q] do
    Logger.debug("Potion menu cancelled")
    %{state | user_messages: ["Cancelled." | state.user_messages], mode: :game}
  end

  defp update_potion_menu(state, msg) do
    Logger.debug("Ignoring input in potion menu: #{inspect(msg)}")
    state
  end

  defp apply_potion(state, ch) do
    index = ch - ?1
    Logger.debug("Potion selection: #{ch} (index: #{index})")

    if index < length(state.inventory.potions) do
      {potion, new_potions} = List.pop_at(state.inventory.potions, index)
      new_state = Items.apply_potion_effect(state, potion, new_potions)
      Logger.debug("Potion applied, transitioning to :game mode")
      %{new_state | mode: :game}
    else
      Logger.debug("Invalid potion choice: #{index}")
      %{state | user_messages: ["Invalid choice." | state.user_messages], mode: :game}
    end
  end

  defp update_dead_mode(state, {:event, %{ch: ?q}}), do: %{state | running: false}
  defp update_dead_mode(state, _msg), do: state

  defp update_explored(state) do
    explored =
      Enum.reduce(0..19, state.explored, fn y, acc ->
        Enum.reduce(0..39, acc, fn x, acc_inner ->
          pos = %Entities.Position{x: x, y: y}

          if Map.is_visible?(state.player.pos, pos, state.map),
            do: MapSet.put(acc_inner, {x, y}),
            else: acc_inner
        end)
      end)

    %{state | explored: explored}
  end

  defp update_explored_and_effects(state) do
    state
    |> update_explored()
    |> update_effects()
  end

  defp update_effects(state) do
    state
    |> update_potion_effects()
    |> update_dot_effects()
    |> increment_turn_count()
    |> despawn_items()
    |> spawn_enemies()
    |> move_enemies()
    |> spawn_weapons()
  end

  defp update_potion_effects(state) do
    if state.effects.turns_left > 0 do
      new_turns = state.effects.turns_left - 1

      if new_turns == 0 do
        %{
          state
          | effects: %{state.effects | damage_mult: 1.0, defense_mult: 1.0, turns_left: 0},
            user_messages: ["Potion effects have worn off." | state.user_messages]
        }
      else
        %{state | effects: %{state.effects | turns_left: new_turns}}
      end
    else
      state
    end
  end

  defp update_dot_effects(state) do
    {new_enemies, dot_messages} =
      Enum.map_reduce(state.enemies, [], fn enemy, acc ->
        if enemy.dot_effect != nil and Entities.Entity.is_alive?(enemy) do
          apply_dot_effect(enemy, acc)
        else
          {enemy, acc}
        end
      end)

    %{state | enemies: new_enemies, user_messages: dot_messages ++ state.user_messages}
  end

  defp apply_dot_effect(enemy, acc) do
    dot = enemy.dot_effect
    {min_dmg, max_dmg} = dot.damage
    damage = Enum.random(min_dmg..max_dmg)
    new_enemy = Entities.Entity.take_damage(enemy, damage)

    msg =
      "#{enemy.symbol} takes #{damage} #{dot.type} damage! (#{new_enemy.hp}/#{new_enemy.max_hp} HP left)"

    new_turns = dot.turns_left - 1

    if new_turns <= 0,
      do:
        {%{new_enemy | dot_effect: nil},
         [msg, "#{enemy.symbol}'s #{dot.type} effect has ended." | acc]},
      else: {%{new_enemy | dot_effect: %{dot | turns_left: new_turns}}, [msg | acc]}
  end

  defp increment_turn_count(state) do
    %{state | turn_count: state.turn_count + 1}
  end

  defp despawn_items(state) do
    {items, despawn_messages} =
      Enum.reduce(state.items, {[], []}, fn item, {items_acc, msg_acc} ->
        if item.damage_range != nil and state.turn_count >= item.despawn_turn do
          {items_acc, ["A #{item.name} has despawned." | msg_acc]}
        else
          {[item | items_acc], msg_acc}
        end
      end)

    %{
      state
      | items: Enum.reverse(items),
        state_messages: despawn_messages ++ state.state_messages
    }
  end

  defp spawn_enemies(state) do
    if state.turn_count >= state.next_spawn_turn do
      enemy = Items.spawn_random_enemy(state.rooms, state.player.pos, state.player_level)

      %{
        state
        | enemies: [enemy | state.enemies],
          next_spawn_turn: state.turn_count + Enum.random(15..25),
          state_messages: [
            "A #{Items.enemy_name(enemy.symbol)} has appeared!" | state.state_messages
          ]
      }
    else
      state
    end
  end

  defp move_enemies(state) do
    Enum.reduce(state.enemies, state, fn enemy, acc ->
      if Entities.Entity.is_alive?(enemy) do
        move_enemy(acc, enemy)
      else
        acc
      end
    end)
  end

  defp move_enemy(state, enemy) do
    if Map.is_visible?(enemy.pos, state.player.pos, state.map) do
      move_toward_player(state, enemy)
    else
      move_randomly(state, enemy)
    end
  end

  defp move_toward_player(state, enemy) do
    direction = get_direction_toward(enemy.pos, state.player.pos)
    new_pos = Entities.Position.move(enemy.pos, direction.dx, direction.dy)

    if new_pos == state.player.pos do
      Combat.combat(state, enemy, state.player)
    else
      try_move_enemy(state, enemy, new_pos)
    end
  end

  defp move_randomly(state, enemy) do
    direction = Enum.random([{0, 1}, {0, -1}, {1, 0}, {-1, 0}])
    new_pos = Entities.Position.move(enemy.pos, elem(direction, 0), elem(direction, 1))
    try_move_enemy(state, enemy, new_pos)
  end

  defp try_move_enemy(state, enemy, new_pos) do
    if Map.is_valid_move?(new_pos, state.map) and
         not Enum.any?(state.enemies, fn e ->
           e.pos == new_pos and Entities.Entity.is_alive?(e)
         end) do
      %{
        state
        | enemies:
            Enum.map(state.enemies, fn e -> if e == enemy, do: %{e | pos: new_pos}, else: e end)
      }
    else
      state
    end
  end

  defp spawn_weapons(state) do
    if state.turn_count >= state.next_weapon_spawn_turn do
      weapon = Items.spawn_random_weapon(state.rooms, state.player.pos, state.items)

      %{
        state
        | items: [weapon | state.items],
          next_weapon_spawn_turn: state.turn_count + Enum.random(15..25),
          state_messages: ["A #{weapon.name} has appeared!" | state.state_messages]
      }
    else
      state
    end
  end

  defp get_direction_toward(enemy_pos, player_pos) do
    dx =
      if player_pos.x > enemy_pos.x, do: 1, else: if(player_pos.x < enemy_pos.x, do: -1, else: 0)

    dy =
      if player_pos.y > enemy_pos.y, do: 1, else: if(player_pos.y < enemy_pos.y, do: -1, else: 0)

    if dx != 0 and dy != 0 and :rand.uniform() < 0.5,
      do: %{dx: dx, dy: 0},
      else: %{dx: 0, dy: dy}
  end
end
