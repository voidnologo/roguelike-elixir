defmodule Roguelike.GameMap do
  alias Roguelike.Entities

  @map_width 40
  @map_height 20
  @wall "#"
  @floor "."
  @visibility_radius 5

  def generate_map do
    map =
      for y <- 0..(@map_height - 1), into: %{} do
        {y,
         for x <- 0..(@map_width - 1), into: %{} do
           {x, @wall}
         end}
      end

    rooms = split_space(0, 0, @map_width, @map_height, 6)
    map_with_rooms = carve_rooms(map, rooms)
    map_with_corridors = connect_all_rooms(map_with_rooms, rooms)
    %{map: map_with_corridors, rooms: rooms}
  end

  defp split_space(x, y, w, h, depth) when depth <= 0 or w < 8 or h < 8 do
    room_w = min(w - 2, Enum.random(4..8))
    room_h = min(h - 2, Enum.random(4..8))
    room_x = x + Enum.random(1..max(1, w - room_w - 1))
    room_y = y + Enum.random(1..max(1, h - room_h - 1))
    [%Entities.Room{x: room_x, y: room_y, w: room_w, h: room_h}]
  end

  defp split_space(x, y, w, h, depth) do
    if w >= h and w >= 8 do
      split = Enum.random(4..max(4, w - 4))
      split_space(x, y, split, h, depth - 1) ++ split_space(x + split, y, w - split, h, depth - 1)
    else
      split = Enum.random(4..max(4, h - 4))
      split_space(x, y, w, split, depth - 1) ++ split_space(x, y + split, w, h - split, depth - 1)
    end
  end

  defp carve_rooms(map, rooms) do
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
  end

  defp connect_all_rooms(map, rooms) do
    Enum.reduce(Enum.zip(rooms, tl(rooms ++ [hd(rooms)])), map, fn {room_a, room_b}, acc ->
      center_a = Entities.Room.center(room_a)
      center_b = Entities.Room.center(room_b)
      acc = draw_hline(acc, center_a.x, center_b.x, center_a.y)
      acc = draw_vline(acc, center_a.y, center_b.y, center_b.x)
      door_y = div(center_a.y + center_b.y, 2)

      if acc[door_y][center_b.x] == @floor,
        do: put_in_map(acc, door_y, center_b.x, "+"),
        else: acc
    end)
  end

  defp draw_hline(map, x1, x2, y) do
    Enum.reduce(min(x1, x2)..max(x1, x2), map, fn x, acc ->
      if x >= 0 and x < @map_width and y >= 0 and y < @map_height,
        do: put_in_map(acc, y, x, @floor),
        else: acc
    end)
  end

  defp draw_vline(map, y1, y2, x) do
    Enum.reduce(min(y1, y2)..max(y1, y2), map, fn y, acc ->
      if x >= 0 and x < @map_width and y >= 0 and y < @map_height,
        do: put_in_map(acc, y, x, @floor),
        else: acc
    end)
  end

  def put_in_map(map, y, x, value), do: Map.update!(map, y, &Map.put(&1, x, value))

  def place_entity_in_room(rooms, exclude) do
    room = Enum.random(rooms)

    pos = %Entities.Position{
      x: Enum.random(room.x..(room.x + room.w - 1)),
      y: Enum.random(room.y..(room.y + room.h - 1))
    }

    if exclude == nil or pos != exclude, do: pos, else: place_entity_in_room(rooms, exclude)
  end

  def is_valid_move?(pos, map) do
    pos.x >= 0 and pos.x < @map_width and pos.y >= 0 and pos.y < @map_height and
      map[pos.y][pos.x] != @wall
  end

  def is_visible?(player_pos, pos, map) do
    distance = Entities.Position.distance_to(player_pos, pos)
    if distance > @visibility_radius, do: false, else: line_of_sight?(player_pos, pos, map)
  end

  defp line_of_sight?(start_pos, end_pos, map) do
    {x0, y0} = {start_pos.x, start_pos.y}
    {x1, y1} = {end_pos.x, end_pos.y}
    dx = abs(x1 - x0)
    dy = abs(y1 - y0)
    sx = if x0 < x1, do: 1, else: -1
    sy = if y0 < y1, do: 1, else: -1
    err = dx - dy
    check_los(x0, y0, x1, y1, dx, dy, sx, sy, err, map)
  end

  defp check_los(x, y, x1, y1, dx, dy, sx, sy, err, map) do
    if x == x1 and y == y1 do
      true
    else
      tile = map[y][x]

      if tile in ["#", "+"] and {x, y} != {x1, y1} do
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
end
