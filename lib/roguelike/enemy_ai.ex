defmodule Roguelike.EnemyAI do
  alias Roguelike.Entities
  alias Roguelike.Combat
  alias Roguelike.GameMap
  require Logger

  def move_enemies(state) do
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
    is_orthogonal_adjacent = (dx == 0 and abs(dy) == 1) or (dy == 0 and abs(dx) == 1)

    cond do
      enemy.rushing ->
        handle_rush(state, enemy, player_pos, dx, dy)

      is_orthogonal_adjacent ->
        handle_attack(state, enemy)

      distance <= 3 ->
        handle_tense(state, enemy, distance)

      true ->
        chase_player(state, enemy, dx, dy)
    end
  end

  defp handle_rush(state, enemy, player_pos, dx, dy) do
    Logger.debug("#{enemy.symbol} rushes player from #{inspect(enemy.pos)}")
    new_enemy = %{enemy | rushing: false}

    direction =
      if abs(dx) > abs(dy),
        do: if(dx > 0, do: %{dx: 1, dy: 0}, else: %{dx: -1, dy: 0}),
        else: if(dy > 0, do: %{dx: 0, dy: 1}, else: %{dx: 0, dy: -1})

    new_pos =
      if dx != 0 and dy != 0,
        do: Entities.Position.move(enemy.pos, direction.dx, direction.dy),
        else: %Entities.Position{
          x:
            if(dx > 0,
              do: player_pos.x - 1,
              else: if(dx < 0, do: player_pos.x + 1, else: player_pos.x)
            ),
          y:
            if(dy > 0,
              do: player_pos.y - 1,
              else: if(dy < 0, do: player_pos.y + 1, else: player_pos.y)
            )
        }

    new_state =
      if GameMap.is_valid_move?(new_pos, state.map) and
           not Enum.any?(state.enemies, fn e ->
             e.pos == new_pos and Entities.Entity.is_alive?(e) and e != enemy
           end) do
        Logger.debug("#{enemy.symbol} moves to #{inspect(new_pos)} to attack")

        %{
          state
          | enemies:
              Enum.map(state.enemies, fn e ->
                if e == enemy, do: %{new_enemy | pos: new_pos}, else: e
              end)
        }
      else
        Logger.debug("#{enemy.symbol} rush blocked, staying at #{inspect(enemy.pos)}")

        %{
          state
          | enemies: Enum.map(state.enemies, fn e -> if e == enemy, do: new_enemy, else: e end)
        }
      end

    new_dx = player_pos.x - new_pos.x
    new_dy = player_pos.y - new_pos.y

    if (new_dx == 0 and abs(new_dy) == 1) or (new_dy == 0 and abs(new_dx) == 1) do
      Combat.combat(new_state, new_enemy, state.player)
    else
      new_state
    end
  end

  defp handle_attack(state, enemy) do
    Logger.debug("#{enemy.symbol} attacks player from #{inspect(enemy.pos)}")
    Combat.combat(state, enemy, state.player)
  end

  defp handle_tense(state, enemy, distance) do
    Logger.debug("#{enemy.symbol} tenses up at #{inspect(enemy.pos)}, distance: #{distance}")

    %{
      state
      | enemies:
          Enum.map(state.enemies, fn e -> if e == enemy, do: %{e | rushing: true}, else: e end),
        user_messages: ["#{enemy.symbol} tenses up, preparing to strike!" | state.user_messages]
    }
  end

  defp chase_player(state, enemy, dx, dy) do
    new_enemy = %{enemy | rushing: false}

    direction =
      if abs(dx) > abs(dy),
        do: if(dx > 0, do: %{dx: 1, dy: 0}, else: %{dx: -1, dy: 0}),
        else: if(dy > 0, do: %{dx: 0, dy: 1}, else: %{dx: 0, dy: -1})

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
              if e == enemy, do: %{new_enemy | pos: new_pos}, else: e
            end)
      }
    else
      try_alternate_path(state, enemy, new_enemy, dx, dy)
    end
  end

  defp try_alternate_path(state, enemy, new_enemy, dx, dy) do
    alt_direction =
      if dx != 0,
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
              if e == enemy, do: %{new_enemy | pos: alt_pos}, else: e
            end)
      }
    else
      Logger.debug("#{enemy.symbol} blocked, staying at #{inspect(enemy.pos)}")

      %{
        state
        | enemies: Enum.map(state.enemies, fn e -> if e == enemy, do: new_enemy, else: e end)
      }
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
end
