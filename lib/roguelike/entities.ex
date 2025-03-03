defmodule Roguelike.Entities do
  defmodule Position do
    defstruct x: 0, y: 0

    def move(pos, dx, dy) do
      %Position{x: pos.x + dx, y: pos.y + dy}
    end

    def distance_to(pos1, pos2) do
      abs(pos1.x - pos2.x) + abs(pos1.y - pos2.y)
    end
  end

  defmodule Room do
    defstruct x: 0, y: 0, w: 0, h: 0

    def center(room) do
      %Position{
        x: round(room.x + room.w / 2),
        y: round(room.y + room.h / 2)
      }
    end
  end

  defmodule Entity do
    defstruct pos: %Position{},
              hp: 0,
              max_hp: 0,
              symbol: "",
              damage_range: {0, 0},
              xp_value: 0,
              dot_effect: nil,
              rushing: false

    def is_alive?(entity) do
      entity.hp > 0
    end

    def get_damage({min, max}) do
      Enum.random(min..max)
    end

    def take_damage(entity, damage) do
      new_hp = max(0, entity.hp - damage)
      %{entity | hp: new_hp}
    end
  end

  defmodule Item do
    defstruct pos: %Position{},
              name: "",
              symbol: "",
              spawn_turn: 0,
              despawn_turn: 0,
              damage_range: nil,
              dot: nil,
              area_effect: nil,
              life_drain: nil,
              hp_restore: nil,
              damage_mult: nil,
              defense_mult: nil,
              duration: nil
  end
end
