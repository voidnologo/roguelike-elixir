defmodule Roguelike.Core do
  alias Roguelike.Combat
  alias Roguelike.Entities
  alias Roguelike.GameMap
  alias Roguelike.Items

  require Logger

  def init(map_data) do
    player = %Entities.Entity{
      pos: GameMap.place_entity_in_room(map_data.rooms, nil),
      hp: 20,
      max_hp: 20,
      symbol: "@"
    }

    initial_state = %{
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

    update_explored(initial_state)
  end

  def update(state, {:event, %{key: ?w}}) do
    move_player(state, 0, -1)
  end

  def update(state, {:event, %{key: ?s}}) do
    move_player(state, 0, 1)
  end

  def update(state, {:event, %{key: ?a}}) do
    move_player(state, -1, 0)
  end

  def update(state, {:event, %{key: ?d}}) do
    move_player(state, 1, 0)
  end

  def update(%{mode: :game} = state, {:event, %{key: ?i}}) do
    Items.inspect_inventory(state)
    |> Map.put(:mode, :inventory)
  end

  def update(%{mode: :game} = state, {:event, %{key: ?u}}) do
    if state.inventory.potions == [] do
      %{state | user_messages: ["No potions available" | state.user_messages]}
    else
      %{state | mode: :potion_menu}
    end
  end

  def update(%{mode: :inventory} = state, {:event, %{key: ?i}}) do
    update_inventory_mode(state, {:event, %{key: ?i}})
  end

  def update(%{mode: :inventory} = state, msg), do: update_inventory_mode(state, msg)

  def update(%{mode: :potion_menu} = state, {:event, %{key: ch}}) when ch in ?1..?9 do
    apply_potion(state, ch)
  end

  def update(%{mode: :potion_menu} = state, {:event, %{key: ch}}) when ch in [?u, ?q] do
    Logger.debug("Potion menu cancelled")
    %{state | user_messages: ["Cancelled." | state.user_messages], mode: :game}
  end

  def update(%{mode: :potion_menu} = state, msg), do: update_potion_menu(state, msg)

  def update(state, msg) do
    Logger.debug("Ignoring input: #{inspect(msg)}")
    state
  end

  defp move_player(state, dx, dy) do
    old_pos = state.player.pos
    new_pos = Entities.Position.move(old_pos, dx, dy)
    Logger.debug("Attempting move from #{inspect(old_pos)} to #{inspect(new_pos)}")

    cond do
      Enum.any?(state.enemies, fn e -> e.pos == new_pos and Entities.Entity.is_alive?(e) end) ->
        enemy = Enum.find(state.enemies, &(&1.pos == new_pos))
        Logger.debug("Attacking enemy #{enemy.symbol} at #{inspect(new_pos)}")
        new_state = Combat.combat(state, state.player, enemy)
        Logger.debug("Combat returned: #{inspect(new_state.user_messages)}")
        update_explored(new_state)

      GameMap.is_valid_move?(new_pos, state.map) ->
        handle_valid_move(state, old_pos, new_pos)
        |> update_explored()

      true ->
        Logger.debug(
          "Move blocked at #{inspect(new_pos)}: #{Map.get(state.map[new_pos.y], new_pos.x, "#")}"
        )

        update_explored_and_effects(state)
    end
  end

  defp handle_valid_move(state, old_pos, new_pos) do
    enemy_at_new_pos =
      Enum.find(state.enemies, fn e -> e.pos == new_pos and Entities.Entity.is_alive?(e) end)

    if enemy_at_new_pos do
      Logger.debug("Attacking enemy #{enemy_at_new_pos.symbol} at #{inspect(new_pos)}")
      new_state = Combat.combat(state, state.player, enemy_at_new_pos)
      update_effects(new_state)
    else
      process_tile(state, old_pos, new_pos)
    end
  end

  defp process_tile(state, _old_pos, new_pos) do
    tile = state.map[new_pos.y][new_pos.x]

    case tile do
      "+" ->
        new_map = GameMap.put_in_map(state.map, new_pos.y, new_pos.x, "/")
        update_effects(%{state | map: new_map})

      "/" ->
        new_player = %{state.player | pos: new_pos}
        new_state = %{state | player: new_player}
        Items.pickup_item(new_state, new_pos) |> update_effects()

      "." ->
        new_player = %{state.player | pos: new_pos}
        new_state = %{state | player: new_player}
        Items.pickup_item(new_state, new_pos) |> update_effects()

      _ ->
        new_player = %{state.player | pos: new_pos}
        new_state = %{state | player: new_player}
        Items.pickup_item(new_state, new_pos) |> update_effects()
    end
  end

  defp update_inventory_mode(state, {:event, %{key: ?i}}) do
    Logger.debug("Exiting inventory mode")
    %{state | mode: :game, user_messages: []}
  end

  defp update_inventory_mode(state, msg) do
    Logger.debug("Ignoring input in inventory mode: #{inspect(msg)}")
    state
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

  defp update_explored(state) do
    new_visible =
      Enum.reduce(0..19, MapSet.new(), fn y, acc ->
        Enum.reduce(0..39, acc, fn x, acc_inner ->
          pos = %Entities.Position{x: x, y: y}

          if GameMap.is_visible?(state.player.pos, pos, state.map) do
            MapSet.put(acc_inner, {x, y})
          else
            acc_inner
          end
        end)
      end)

    explored = MapSet.union(state.explored, new_visible)
    # Logger.debug("Updated ExploredTiles: #{inspect(explored)}")
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
    if GameMap.is_visible?(enemy.pos, state.player.pos, state.map) do
      move_toward_player(state, enemy)
    else
      move_randomly(state, enemy)
    end
  end

  defp move_toward_player(state, enemy) do
    player_pos = state.player.pos
    enemy_pos = enemy.pos
    dx = player_pos.x - enemy_pos.x
    dy = player_pos.y - enemy_pos.y
    distance = Entities.Position.distance_to(enemy_pos, player_pos)

    cond do
      # If rushing from last turn, charge and attack
      enemy.rushing ->
        Logger.debug("#{enemy.symbol} rushes player from #{inspect(enemy_pos)}")
        new_enemy = %{enemy | rushing: false}

        new_state =
          if distance <= 2 and GameMap.is_valid_move?(player_pos, state.map) do
            %{
              state
              | enemies:
                  Enum.map(state.enemies, fn e ->
                    if e == enemy, do: %{new_enemy | pos: player_pos}, else: e
                  end)
            }
          else
            %{
              state
              | enemies:
                  Enum.map(state.enemies, fn e -> if e == enemy, do: new_enemy, else: e end)
            }
          end

        Combat.combat(new_state, new_enemy, state.player)

      # If adjacent, attack immediately
      distance <= 1 ->
        Logger.debug("#{enemy.symbol} attacks player from #{inspect(enemy_pos)}")
        Combat.combat(state, enemy, state.player)

      # If within 2 tiles, tense up for next turn's rush
      distance <= 2 ->
        Logger.debug("#{enemy.symbol} tenses up at #{inspect(enemy_pos)}")

        %{
          state
          | enemies:
              Enum.map(state.enemies, fn e -> if e == enemy, do: %{e | rushing: true}, else: e end),
            user_messages: [
              "#{enemy.symbol} tenses up, preparing to strike!" | state.user_messages
            ]
        }

      # Otherwise, chase as before
      true ->
        direction =
          if abs(dx) > abs(dy) do
            if dx > 0, do: %{dx: 1, dy: 0}, else: %{dx: -1, dy: 0}
          else
            if dy > 0, do: %{dx: 0, dy: 1}, else: %{dx: 0, dy: -1}
          end

        new_pos = Entities.Position.move(enemy.pos, direction.dx, direction.dy)

        if GameMap.is_valid_move?(new_pos, state.map) and
             not Enum.any?(state.enemies, fn e ->
               e.pos == new_pos and Entities.Entity.is_alive?(e) and e != enemy
             end) do
          Logger.debug("#{enemy.symbol} moves toward player to #{inspect(new_pos)}")

          %{
            state
            | enemies:
                Enum.map(state.enemies, fn e ->
                  if e == enemy, do: %{e | pos: new_pos}, else: e
                end)
          }
        else
          alt_direction =
            if direction.dx != 0,
              do: if(dy > 0, do: %{dx: 0, dy: 1}, else: %{dx: 0, dy: -1}),
              else: if(dx > 0, do: %{dx: 1, dy: 0}, else: %{dx: -1, dy: 0})

          alt_pos = Entities.Position.move(enemy.pos, alt_direction.dx, alt_direction.dy)

          if GameMap.is_valid_move?(alt_pos, state.map) and
               not Enum.any?(state.enemies, fn e ->
                 e.pos == alt_pos and Entities.Entity.is_alive?(e) and e != enemy
               end) do
            Logger.debug("#{enemy.symbol} takes alternate path to #{inspect(alt_pos)}")

            %{
              state
              | enemies:
                  Enum.map(state.enemies, fn e ->
                    if e == enemy, do: %{e | pos: alt_pos}, else: e
                  end)
            }
          else
            Logger.debug("#{enemy.symbol} blocked, staying at #{inspect(enemy.pos)}")
            state
          end
        end
    end
  end

  defp move_randomly(state, enemy) do
    direction = Enum.random([{0, 1}, {0, -1}, {1, 0}, {-1, 0}])
    new_pos = Entities.Position.move(enemy.pos, elem(direction, 0), elem(direction, 1))

    if GameMap.is_valid_move?(new_pos, state.map) and
         not Enum.any?(state.enemies, fn e ->
           e.pos == new_pos and Entities.Entity.is_alive?(e) and e != enemy
         end) do
      Logger.debug("#{enemy.symbol} moves randomly to #{inspect(new_pos)}")

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
end
