defmodule Roguelike do
  @reset "\e[0m"
  @red "\e[31m"
  @cyan "\e[36m"
  @magenta "\e[35m"
  @green "\e[32m"
  @yellow "\e[33m"
  @gray "\e[90m"

  @map_width 40
  @map_height 20
  @wall "#"
  @floor "."
  @player "@"
  @door_closed "+"
  @door_open "/"
  @fog " "
  @visibility_radius 5
  @player_base_hp 20
  @xp_per_level 100
  @spawn_min 15
  @spawn_max 25
  @weapon_despawn_min 20
  @weapon_despawn_max 30
  @weapon_spawn_min 15
  @weapon_spawn_max 25
  @potion_duration 10
  @dot_duration 3
  @special_weapon_chance 0.2

  require Logger

  defmodule Position do
    defstruct x: 0, y: 0

    def move(pos, dx, dy), do: %Position{x: pos.x + dx, y: pos.y + dy}

    def distance_to(pos1, pos2) do
      :math.sqrt(:math.pow(pos1.x - pos2.x, 2) + :math.pow(pos1.y - pos2.y, 2))
    end
  end

  defmodule Entity do
    defstruct pos: %Position{},
              hp: 0,
              max_hp: 0,
              symbol: "",
              damage_range: {1, 3},
              xp_value: 0,
              dot_effect: nil

    def take_damage(entity, damage) do
      new_hp = max(0, entity.hp - damage)
      %{entity | hp: new_hp}
    end

    def is_alive?(entity), do: entity.hp > 0

    def get_damage({min, max}), do: Enum.random(min..max)
  end

  defmodule Item do
    defstruct pos: %Position{},
              name: "",
              symbol: "",
              spawn_turn: 0,
              despawn_turn: 0,
              damage_range: nil,
              hp_restore: nil,
              damage_mult: nil,
              defense_mult: nil,
              duration: nil,
              dot: nil,
              area_effect: nil,
              life_drain: nil
  end

  defmodule Room do
    defstruct x: 0, y: 0, w: 0, h: 0

    def center(room) do
      %Position{x: room.x + div(room.w, 2), y: room.y + div(room.h, 2)}
    end
  end

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

  @enemy_symbols Enum.map(@enemy_types, fn {_, stats} -> stats.symbol end)

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
      dot: %{type: "fire", damage: {1, 3}, duration: @dot_duration}
    },
    "Poison Dagger" => %{
      damage_range: {2, 4},
      symbol: "q",
      dot: %{type: "poison", damage: {1, 2}, duration: @dot_duration}
    },
    "Explosive Axe" => %{damage_range: {4, 8}, symbol: "x", area_effect: true},
    "Vampiric Mace" => %{damage_range: {3, 7}, symbol: "v", life_drain: 0.25}
  }

  @weapon_symbols Enum.map(@weapon_types, fn {_, stats} -> stats.symbol end)

  @potion_types %{
    "Health Potion" => %{hp_restore: {5, 10}, symbol: "h"},
    "Damage Potion" => %{damage_mult: 1.5, symbol: "D", duration: @potion_duration},
    "Defense Potion" => %{defense_mult: 0.5, symbol: "F", duration: @potion_duration}
  }

  @potion_symbols Enum.map(@potion_types, fn {_, stats} -> stats.symbol end)

  def init(map_data) do
    player = %Entity{
      pos: place_entity_in_room(map_data.rooms, nil),
      hp: @player_base_hp,
      max_hp: @player_base_hp,
      symbol: @player
    }

    enemies = spawn_initial_enemies(map_data.rooms, player.pos)
    items = spawn_items(map_data.rooms, player.pos)

    %{
      map: map_data.map,
      rooms: map_data.rooms,
      player: player,
      enemies: enemies,
      items: items,
      explored: MapSet.new(),
      player_xp: 0,
      player_level: 1,
      turn_count: 0,
      next_spawn_turn: Enum.random(@spawn_min..@spawn_max),
      next_weapon_spawn_turn: Enum.random(@weapon_spawn_min..@weapon_spawn_max),
      inventory: %{weapon: nil, potions: []},
      effects: %{damage_mult: 1.0, defense_mult: 1.0, turns_left: 0},
      current_weapon_effects: %{},
      messages: [],
      mode: :game
    }
  end

  def update(state, msg) do
    case state.mode do
      :game ->
        case msg do
          {:event, %{ch: ?q}} ->
            %{state | running: false}

          {:event, %{ch: ?i}} when state.player.hp > 0 ->
            inspect_inventory(state)

          {:event, %{ch: ?u}} when state.player.hp > 0 ->
            %{state | mode: :potion_menu}

          {:event, %{key: key}} when key in [?w, ?s, ?a, ?d] and state.player.hp > 0 ->
            {dx, dy} =
              case key do
                ?w -> {0, -1}
                ?s -> {0, 1}
                ?a -> {-1, 0}
                ?d -> {1, 0}
              end

            old_pos = state.player.pos
            new_pos = Position.move(state.player.pos, dx, dy)

            Logger.debug("Moving from #{inspect(old_pos)} to #{inspect(new_pos)}")

            if is_valid_move?(new_pos, state.map) do
              tile = state.map[new_pos.y][new_pos.x]

              # Clear old player position
              new_map = put_in_map(state.map, old_pos.y, old_pos.x, @floor)
              Logger.debug("Old position cleared: #{inspect({old_pos.x, old_pos.y})} set to '.'")

              case tile do
                @door_closed ->
                  new_map = put_in_map(new_map, new_pos.y, new_pos.x, @door_open)
                  update_effects(%{state | map: new_map})

                @door_open ->
                  new_player = %{state.player | pos: new_pos}

                  new_state = %{
                    state
                    | map: new_map,
                      player: new_player,
                      explored: MapSet.put(state.explored, {new_pos.x, new_pos.y})
                  }

                  Enum.reduce(new_state.enemies, new_state, fn enemy, acc ->
                    if enemy.pos == new_pos and Entity.is_alive?(enemy),
                      do: combat(acc, acc.player, enemy),
                      else: acc
                  end)
                  |> pickup_item(new_pos)
                  |> update_effects()

                @floor ->
                  new_player = %{state.player | pos: new_pos}

                  new_state = %{
                    state
                    | map: new_map,
                      player: new_player,
                      explored: MapSet.put(state.explored, {new_pos.x, new_pos.y})
                  }

                  Enum.reduce(new_state.enemies, new_state, fn enemy, acc ->
                    if enemy.pos == new_pos and Entity.is_alive?(enemy),
                      do: combat(acc, acc.player, enemy),
                      else: acc
                  end)
                  |> pickup_item(new_pos)
                  |> update_effects()

                # Safeguard for unexpected tiles
                _ ->
                  new_player = %{state.player | pos: new_pos}

                  new_state = %{
                    state
                    | map: new_map,
                      player: new_player,
                      explored: MapSet.put(state.explored, {new_pos.x, new_pos.y})
                  }

                  Enum.reduce(new_state.enemies, new_state, fn enemy, acc ->
                    if enemy.pos == new_pos and Entity.is_alive?(enemy),
                      do: combat(acc, acc.player, enemy),
                      else: acc
                  end)
                  |> pickup_item(new_pos)
                  |> update_effects()
              end
            else
              Logger.debug(
                "Move blocked at #{inspect(new_pos)}: #{Map.get(state.map[new_pos.y], new_pos.x, "#")}"
              )

              update_effects(state)
            end

          _ ->
            update_effects(state)
        end

      :potion_menu ->
        case msg do
          {:event, %{ch: ch}} when ch in ?1..?9 ->
            index = ch - ?1

            if index < length(state.inventory.potions) do
              {potion, new_potions} = List.pop_at(state.inventory.potions, index)

              new_state =
                case potion do
                  %{hp_restore: {min, max}} ->
                    heal = Enum.random(min..max)

                    new_player = %{
                      state.player
                      | hp: min(state.player.max_hp, state.player.hp + heal)
                    }

                    %{
                      state
                      | player: new_player,
                        inventory: %{state.inventory | potions: new_potions},
                        messages: [
                          "Used #{potion.name}! Restored #{heal} HP. (#{new_player.hp}/#{new_player.max_hp})"
                        ]
                    }

                  %{damage_mult: mult, duration: dur} ->
                    %{
                      state
                      | effects: %{state.effects | damage_mult: mult, turns_left: dur},
                        inventory: %{state.inventory | potions: new_potions},
                        messages: [
                          "Used #{potion.name}! Damage increased to x#{mult} for #{dur} turns."
                        ]
                    }

                  %{defense_mult: mult, duration: dur} ->
                    %{
                      state
                      | effects: %{state.effects | defense_mult: mult, turns_left: dur},
                        inventory: %{state.inventory | potions: new_potions},
                        messages: [
                          "Used #{potion.name}! Damage reduced to x#{mult} for #{dur} turns."
                        ]
                    }
                end

              :timer.sleep(1000)
              %{new_state | mode: :game}
            else
              %{state | messages: ["Invalid choice."], mode: :game}
            end

          _ ->
            %{state | messages: ["Cancelled."], mode: :game}
        end
    end
  end

  def render_game(state) do
    render_map =
      Enum.reduce(state.enemies, state.map, fn enemy, acc ->
        if Entity.is_alive?(enemy) and is_visible?(state.player.pos, enemy.pos, acc),
          do: put_in_map(acc, enemy.pos.y, enemy.pos.x, enemy.symbol),
          else: acc
      end)

    render_map =
      Enum.reduce(state.items, render_map, fn item, acc ->
        if is_visible?(state.player.pos, item.pos, acc),
          do: put_in_map(acc, item.pos.y, item.pos.x, item.symbol),
          else: acc
      end)

    enemy_hp =
      Enum.map_join(Enum.filter(state.enemies, &Entity.is_alive?/1), " | ", fn e ->
        "#{@red}#{e.symbol}#{@reset}: #{e.hp}/#{e.max_hp}"
      end)

    effects_str =
      if state.effects.turns_left > 0,
        do:
          "Effects: Dmg x#{state.effects.damage_mult}, Def x#{state.effects.defense_mult} (#{state.effects.turns_left} turns)",
        else: "Effects: None"

    legend = "Symbols: "

    # Filter visible entities, safely handling Items vs Entities
    visible_entities =
      Enum.filter(state.items ++ state.enemies, fn entity ->
        is_visible?(state.player.pos, entity.pos, state.map) and
          (match?(%Roguelike.Item{}, entity) or Entity.is_alive?(entity))
      end)

    symbol_meanings =
      Enum.map(visible_entities, fn entity ->
        symbol = entity.symbol

        cond do
          symbol in @enemy_symbols ->
            name = Enum.find_value(@enemy_types, fn {k, v} -> if v.symbol == symbol, do: k end)
            "#{@red}#{symbol}#{@reset}=#{name}"

          symbol in @weapon_symbols ->
            name = Enum.find_value(@weapon_types, fn {k, v} -> if v.symbol == symbol, do: k end)

            color =
              if Enum.any?(@weapon_types, fn {_, v} ->
                   v.symbol == symbol and (v[:dot] || v[:area_effect] || v[:life_drain])
                 end),
                 do: @magenta,
                 else: @cyan

            "#{color}#{symbol}#{@reset}=#{name}"

          symbol in @potion_symbols ->
            name = Enum.find_value(@potion_types, fn {k, v} -> if v.symbol == symbol, do: k end)
            "#{@green}#{symbol}#{@reset}=#{name}"

          true ->
            nil
        end
      end)
      |> Enum.filter(& &1)
      |> Enum.uniq()

    map_lines =
      for y <- 0..(@map_height - 1) do
        row =
          for x <- 0..(@map_width - 1), into: "" do
            pos = %Position{x: x, y: y}
            tile = render_map[y][x]

            cond do
              pos == state.player.pos ->
                "#{@yellow}#{@player}#{@reset}"

              is_visible?(state.player.pos, pos, render_map) ->
                case tile do
                  symbol when symbol in @enemy_symbols ->
                    "#{@red}#{symbol}#{@reset}"

                  symbol when symbol in @weapon_symbols ->
                    if Enum.any?(@weapon_types, fn {_, v} ->
                         v.symbol == symbol and (v[:dot] || v[:area_effect] || v[:life_drain])
                       end),
                       do: "#{@magenta}#{symbol}#{@reset}",
                       else: "#{@cyan}#{symbol}#{@reset}"

                  symbol when symbol in @potion_symbols ->
                    "#{@green}#{symbol}#{@reset}"

                  @wall ->
                    "#{@gray}#{tile}#{@reset}"

                  _ ->
                    tile
                end

              MapSet.member?(state.explored, {x, y}) ->
                if tile == @wall, do: "#{@gray}#{tile}#{@reset}", else: tile

              true ->
                @fog
            end
          end

        %{content: row}
      end

    status_lines =
      Enum.reverse(
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
          %{
            content:
              legend <>
                if(symbol_meanings != [],
                  do: Enum.join(symbol_meanings, ", "),
                  else: "None visible"
                )
          }
        ] ++ Enum.map(Enum.take(state.messages, -10), fn msg -> %{content: msg} end)
      )

    case state.mode do
      :game ->
        map_lines ++ status_lines

      :potion_menu ->
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

        [
          %{
            content:
              "Use Potion (Select 1-#{length(state.inventory.potions)} or any key to cancel)"
          }
        ] ++ potion_lines ++ status_lines
    end
  end

  def generate_map do
    map =
      for y <- 0..(@map_height - 1), into: %{} do
        {y,
         for x <- 0..(@map_width - 1), into: %{} do
           {x, @wall}
         end}
      end

    rooms = split_space(0, 0, @map_width, @map_height, 6)

    map_with_rooms =
      Enum.reduce(rooms, map, fn room, acc ->
        Enum.reduce(room.y..(room.y + room.h - 1), acc, fn y, acc_y ->
          if y >= 0 and y < @map_height do
            Enum.reduce(room.x..(room.x + room.w - 1), acc_y, fn x, acc_x ->
              if x >= 0 and x < @map_width do
                Map.update!(acc_x, y, &Map.put(&1, x, @floor))
              else
                acc_x
              end
            end)
          else
            acc_y
          end
        end)
      end)

    map_with_corridors = connect_all_rooms(map_with_rooms, rooms)
    %{map: map_with_corridors, rooms: rooms}
  end

  def split_space(x, y, w, h, depth) when depth <= 0 or w < 8 or h < 8 do
    room_w = min(w - 2, Enum.random(4..8))
    room_h = min(h - 2, Enum.random(4..8))
    room_x = x + Enum.random(1..max(1, w - room_w - 1))
    room_y = y + Enum.random(1..max(1, h - room_h - 1))
    [%Room{x: room_x, y: room_y, w: room_w, h: room_h}]
  end

  def split_space(x, y, w, h, depth) do
    if w >= h and w >= 8 do
      split = Enum.random(4..max(4, w - 4))
      split_space(x, y, split, h, depth - 1) ++ split_space(x + split, y, w - split, h, depth - 1)
    else
      split = Enum.random(4..max(4, h - 4))
      split_space(x, y, w, split, depth - 1) ++ split_space(x, y + split, w, h - split, depth - 1)
    end
  end

  def connect_all_rooms(map, rooms) do
    Enum.reduce(Enum.zip(rooms, tl(rooms ++ [hd(rooms)])), map, fn {room_a, room_b}, acc ->
      center_a = Room.center(room_a)
      center_b = Room.center(room_b)
      acc = draw_hline(acc, center_a.x, center_b.x, center_a.y)
      acc = draw_vline(acc, center_a.y, center_b.y, center_b.x)
      door_y = div(center_a.y + center_b.y, 2)

      if acc[door_y][center_b.x] == @floor,
        do: put_in_map(acc, door_y, center_b.x, @door_closed),
        else: acc
    end)
  end

  def draw_hline(map, x1, x2, y) do
    Enum.reduce(min(x1, x2)..max(x1, x2), map, fn x, acc ->
      if x >= 0 and x < @map_width and y >= 0 and y < @map_height,
        do: put_in_map(acc, y, x, @floor),
        else: acc
    end)
  end

  def draw_vline(map, y1, y2, x) do
    Enum.reduce(min(y1, y2)..max(y1, y2), map, fn y, acc ->
      if x >= 0 and x < @map_width and y >= 0 and y < @map_height,
        do: put_in_map(acc, y, x, @floor),
        else: acc
    end)
  end

  def put_in_map(map, y, x, value), do: Map.update!(map, y, &Map.put(&1, x, value))

  def place_entity_in_room(rooms, exclude) do
    room = Enum.random(rooms)

    pos = %Position{
      x: Enum.random(room.x..(room.x + room.w - 1)),
      y: Enum.random(room.y..(room.y + room.h - 1))
    }

    if exclude == nil or pos != exclude, do: pos, else: place_entity_in_room(rooms, exclude)
  end

  def spawn_initial_enemies(rooms, player_pos) do
    exclude = player_pos

    Enum.map(["Goblin", "Orc", "Troll"], fn enemy_type ->
      stats = @enemy_types[enemy_type]
      # Unpack tuple
      {min_hp, max_hp} = stats.hp_range
      # Convert to range
      hp = Enum.random(min_hp..max_hp)
      pos = place_entity_in_room(rooms, exclude)

      %Entity{
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
      Enum.map(initial_weapons, fn weapon_name ->
        stats = @weapon_types[weapon_name]
        pos = place_entity_in_room(rooms, exclude)

        %Item{
          pos: pos,
          name: weapon_name,
          symbol: stats.symbol,
          spawn_turn: 0,
          despawn_turn: Enum.random(@weapon_despawn_min..@weapon_despawn_max),
          damage_range: stats.damage_range,
          dot: stats[:dot],
          area_effect: stats[:area_effect],
          life_drain: stats[:life_drain]
        }
      end)

    potions =
      Enum.map(@potion_types, fn {potion_name, stats} ->
        pos = place_entity_in_room(rooms, exclude)

        %Item{
          pos: pos,
          name: potion_name,
          symbol: stats.symbol,
          spawn_turn: 0,
          despawn_turn: Enum.random(@weapon_despawn_min..@weapon_despawn_max),
          hp_restore: stats[:hp_restore],
          damage_mult: stats[:damage_mult],
          defense_mult: stats[:defense_mult],
          duration: stats[:duration]
        }
      end)

    weapons ++ potions
  end

  def is_valid_move?(pos, map) do
    pos.x >= 0 and pos.x < @map_width and pos.y >= 0 and pos.y < @map_height and
      map[pos.y][pos.x] != @wall
  end

  def is_visible?(player_pos, pos, map) do
    distance = Position.distance_to(player_pos, pos)
    if distance > @visibility_radius, do: false, else: line_of_sight?(player_pos, pos, map)
  end

  def line_of_sight?(start_pos, end_pos, map) do
    {x0, y0} = {start_pos.x, start_pos.y}
    {x1, y1} = {end_pos.x, end_pos.y}
    dx = abs(x1 - x0)
    dy = abs(y1 - y0)
    sx = if x0 < x1, do: 1, else: -1
    sy = if y0 < y1, do: 1, else: -1
    err = dx - dy

    {x, y} = {x0, y0}
    check_los(x, y, x1, y1, dx, dy, sx, sy, err, map)
  end

  def check_los(x, y, x1, y1, dx, dy, sx, sy, err, map) do
    if x == x1 and y == y1 do
      true
    else
      tile = map[y][x]

      if tile in [@wall, @door_closed] and {x, y} != {x1, y1} do
        false
      else
        e2 = 2 * err
        new_x = if e2 > -dy, do: x + sx, else: x
        new_y = if e2 < dx, do: y + sy, else: y
        new_err = err + if(e2 > -dy, do: -dy, else: 0) + if e2 < dx, do: dx, else: 0
        check_los(new_x, new_y, x1, y1, dx, dy, sx, sy, new_err, map)
      end
    end
  end

  def combat(state, attacker, defender) do
    damage = round(Entity.get_damage(attacker.damage_range) * state.effects.damage_mult)

    reduced_damage =
      round(damage * if(defender == state.player, do: state.effects.defense_mult, else: 1.0))

    new_defender = Entity.take_damage(defender, reduced_damage)

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

    # Safely handle weapon effects
    new_state =
      if attacker == state.player and state.inventory.weapon != nil do
        weapon_stats = @weapon_types[state.inventory.weapon]

        new_state =
          if weapon_stats[:dot] != nil and Entity.is_alive?(new_defender) do
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
              Enum.map(new_state.enemies, fn e -> if e == defender, do: new_defender, else: e end)

            %{
              new_state
              | enemies: new_enemies,
                messages:
                  ["#{new_defender.symbol} is now affected by #{dot.type}!"] ++ new_state.messages
            }
          else
            new_state
          end

        new_state =
          if weapon_stats[:area_effect] != nil and Entity.is_alive?(new_defender) do
            new_enemies =
              Enum.map(new_state.enemies, fn e ->
                if e != new_defender and Entity.is_alive?(e) and
                     Position.distance_to(e.pos, new_defender.pos) <= 1 do
                  area_damage = div(reduced_damage, 2)
                  e = Entity.take_damage(e, area_damage)

                  {e,
                   "#{e.symbol} takes #{area_damage} area damage! (#{e.hp}/#{e.max_hp} HP left)"}
                else
                  {e, nil}
                end
              end)

            {enemies, area_messages} = Enum.unzip(new_enemies)
            area_messages = Enum.filter(area_messages, & &1)
            %{new_state | enemies: enemies, messages: area_messages ++ new_state.messages}
          else
            new_state
          end

        if weapon_stats[:life_drain] != nil do
          heal = round(reduced_damage * weapon_stats.life_drain)

          new_player = %{
            new_state.player
            | hp: min(new_state.player.max_hp, new_state.player.hp + heal)
          }

          %{
            new_state
            | player: new_player,
              messages:
                [
                  "#{attacker.symbol} drains #{heal} HP! (#{new_player.hp}/#{new_player.max_hp} HP)"
                ] ++ new_state.messages
          }
        else
          new_state
        end
      else
        new_state
      end

    new_state = %{new_state | messages: [message] ++ new_state.messages}

    if not Entity.is_alive?(new_defender) and new_defender != state.player do
      new_xp = new_state.player_xp + new_defender.xp_value

      new_messages =
        ["Gained #{new_defender.xp_value} XP! Total XP: #{new_xp}"] ++ new_state.messages

      check_level_up(%{new_state | player_xp: new_xp, messages: new_messages})
    else
      new_state
    end
  end

  def check_level_up(state) do
    new_level = div(state.player_xp, @xp_per_level) + 1

    if new_level > state.player_level do
      new_max_hp = state.player.max_hp + 5
      {min_dmg, max_dmg} = state.player.damage_range
      new_damage_range = {min_dmg + 1, max_dmg + 1}

      message =
        "Level Up! Level #{new_level} - HP: #{new_max_hp}, Damage: #{inspect(new_damage_range)}"

      %{
        state
        | player_level: new_level,
          player: %{
            state.player
            | max_hp: new_max_hp,
              hp: new_max_hp,
              damage_range: new_damage_range
          },
          messages: [message] ++ state.messages
      }
    else
      state
    end
  end

  def pickup_item(state, new_pos) do
    {picked_items, remaining_items} =
      Enum.split_with(state.items, fn item -> item.pos == new_pos end)

    Enum.reduce(picked_items, %{state | items: remaining_items}, fn item, acc ->
      if item.hp_restore || item.damage_mult || item.defense_mult do
        new_potions = [item | acc.inventory.potions]
        message = "Picked up #{item.name}! Added to inventory. Potions: #{length(new_potions)}"

        %{
          acc
          | inventory: %{acc.inventory | potions: new_potions},
            messages: [message] ++ acc.messages
        }
      else
        acc =
          if acc.inventory.weapon do
            # Find the old weapon's stats
            old_weapon =
              Enum.find(@weapon_types, fn {_, v} -> v.damage_range == acc.player.damage_range end)

            # Destructure the tuple correctly
            {old_weapon_name, old_weapon_stats} = old_weapon

            new_items = [
              %Item{
                pos: acc.player.pos,
                name: old_weapon_name,
                symbol: old_weapon_stats.symbol,
                spawn_turn: acc.turn_count,
                despawn_turn:
                  acc.turn_count + Enum.random(@weapon_despawn_min..@weapon_despawn_max),
                damage_range: old_weapon_stats.damage_range
              }
              | acc.items
            ]

            %{
              acc
              | items: new_items,
                messages: ["Dropped #{old_weapon_name}."] ++ acc.messages
            }
          else
            acc
          end

        new_player = %{acc.player | damage_range: item.damage_range}
        message = "Picked up #{item.name}! Damage range now #{inspect(item.damage_range)}."

        %{
          acc
          | player: new_player,
            inventory: %{acc.inventory | weapon: item.name},
            current_weapon_effects: %{
              dot: item.dot,
              area_effect: item.area_effect,
              life_drain: item.life_drain
            },
            messages: [message] ++ acc.messages
        }
      end
    end)
  end

  def update_effects(state) do
    state =
      if state.effects.turns_left > 0 do
        new_turns = state.effects.turns_left - 1

        if new_turns == 0 do
          %{
            state
            | effects: %{state.effects | damage_mult: 1.0, defense_mult: 1.0, turns_left: 0},
              messages: ["Potion effects have worn off."] ++ state.messages
          }
        else
          %{state | effects: %{state.effects | turns_left: new_turns}}
        end
      else
        state
      end

    {new_enemies, messages} =
      Enum.map_reduce(state.enemies, state.messages, fn enemy, acc ->
        if enemy.dot_effect != nil and Entity.is_alive?(enemy) do
          dot = enemy.dot_effect
          {min_dmg, max_dmg} = dot.damage
          damage = Enum.random(min_dmg..max_dmg)
          new_enemy = Entity.take_damage(enemy, damage)

          msg =
            "#{enemy.symbol} takes #{damage} #{dot.type} damage! (#{new_enemy.hp}/#{new_enemy.max_hp} HP left)"

          new_turns = dot.turns_left - 1

          if new_turns <= 0,
            do:
              {%{new_enemy | dot_effect: nil},
               [msg, "#{enemy.symbol}'s #{dot.type} effect has ended."] ++ acc},
            else: {%{new_enemy | dot_effect: %{dot | turns_left: new_turns}}, [msg] ++ acc}
        else
          {enemy, acc}
        end
      end)

    state = %{state | enemies: new_enemies, messages: messages, turn_count: state.turn_count + 1}

    state =
      Enum.reduce(state.items, state, fn item, acc ->
        # Fix: != nil instead of and
        if item.damage_range != nil and acc.turn_count >= item.despawn_turn do
          %{
            acc
            | items: List.delete(acc.items, item),
              messages: ["A #{item.name} has despawned."] ++ acc.messages
          }
        else
          acc
        end
      end)

    state =
      if state.turn_count >= state.next_spawn_turn do
        available_types =
          Enum.filter(@enemy_types, fn {_, stats} -> stats.min_level <= state.player_level end)

        enemy_type = Enum.random(available_types) |> elem(0)
        stats = @enemy_types[enemy_type]
        {min_hp, max_hp} = stats.hp_range
        hp = Enum.random(min_hp..max_hp)
        pos = place_entity_in_room(state.rooms, state.player.pos)

        new_enemy = %Entity{
          pos: pos,
          hp: hp,
          max_hp: hp,
          symbol: stats.symbol,
          damage_range: stats.damage_range,
          xp_value: stats.xp
        }

        %{
          state
          | enemies: [new_enemy | state.enemies],
            next_spawn_turn: state.turn_count + Enum.random(@spawn_min..@spawn_max),
            messages: ["A #{enemy_type} has appeared!"] ++ state.messages
        }
      else
        state
      end

    if state.turn_count >= state.next_weapon_spawn_turn do
      special_weapons =
        Enum.filter(@weapon_types, fn {_, v} -> v[:dot] || v[:area_effect] || v[:life_drain] end)

      regular_weapons =
        Enum.filter(@weapon_types, fn {k, _} ->
          k not in Enum.map(special_weapons, &elem(&1, 0))
        end)

      # Fix here too
      has_special =
        Enum.any?(state.items, fn i ->
          i.damage_range != nil and i.name in Enum.map(special_weapons, &elem(&1, 0))
        end)

      weapon_name =
        if not has_special or :rand.uniform() < @special_weapon_chance,
          do: Enum.random(special_weapons) |> elem(0),
          else: Enum.random(regular_weapons) |> elem(0)

      stats = @weapon_types[weapon_name]
      pos = place_entity_in_room(state.rooms, state.player.pos)

      new_item = %Item{
        pos: pos,
        name: weapon_name,
        symbol: stats.symbol,
        spawn_turn: state.turn_count,
        despawn_turn: state.turn_count + Enum.random(@weapon_spawn_min..@weapon_spawn_max),
        damage_range: stats.damage_range,
        dot: stats[:dot],
        area_effect: stats[:area_effect],
        life_drain: stats[:life_drain]
      }

      %{
        state
        | items: [new_item | state.items],
          next_weapon_spawn_turn:
            state.turn_count + Enum.random(@weapon_spawn_min..@weapon_spawn_max),
          messages: ["A #{weapon_name} has appeared!"] ++ state.messages
      }
    else
      state
    end
  end

  def inspect_inventory(state) do
    weapon = state.inventory.weapon || "None"

    messages = [
      "\nInventory: Equipped Weapon - #{weapon} (Damage: #{inspect(state.player.damage_range)})"
    ]

    messages =
      if state.current_weapon_effects[:dot] do
        dot = state.current_weapon_effects[:dot]

        [
          "  Special: #{String.capitalize(dot.type)} DoT (#{inspect(dot.damage)} dmg for #{dot.duration} turns)"
          | messages
        ]
      else
        messages
      end

    messages =
      if state.current_weapon_effects[:area_effect],
        do: ["  Special: Area Effect" | messages],
        else: messages

    messages =
      if state.current_weapon_effects[:life_drain],
        do: [
          "  Special: Life Drain (#{round(state.current_weapon_effects.life_drain * 100)}% of damage)"
          | messages
        ],
        else: messages

    messages = ["Potions:" | messages]

    messages =
      if Enum.empty?(state.inventory.potions),
        do: ["  None" | messages],
        else:
          Enum.reduce(state.inventory.potions, messages, fn potion, acc ->
            effect =
              cond do
                potion.hp_restore -> "Heals #{inspect(potion.hp_restore)}"
                potion.damage_mult -> "Dmg x#{potion.damage_mult} for #{potion.duration} turns"
                potion.defense_mult -> "Def x#{potion.defense_mult} for #{potion.duration} turns"
              end

            ["  - #{potion.name} (#{effect})" | acc]
          end)

    :timer.sleep(2000)
    %{state | messages: Enum.reverse(messages)}
  end
end
