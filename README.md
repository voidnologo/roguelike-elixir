# Roguelike

**TODO: Add description**
- doors and walls appear randomly, even in middle of room
- maybe figure out terminal package to allow more 'real time' interaction

# To Play
- `wasd` to move
- `u` to open potion menu, `#` to select and apply
- `i` to inspect inventory
- weapons will pick up when you walk over them, dropping current weapon
- player and enemies attack orthogonally
- player will level up every (100 * level), gaining more health and hitting harder
- harder enemies will appear at higher levels.

- I could not get a terminal package working, so you have to press `Enter` between each turn.
- There is a _lot_ of logging.  Recommend you turn logging settings off.

# To Run
- `mix compile`
- `mix run --no-halt`

## Env
- Elixir 1.18
- OTP 27

