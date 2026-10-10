# Pocket Slayer

A tiny top-down monster shooter for the **iPod nano 2nd generation**, running on [Rockbox](https://www.rockbox.org).
You move around and your hero shoots the closest monster by itself, but only while you stand still.

## Controls

| Button | What it does |
|---|---|
| Menu (top) | move up |
| Play (bottom) | move down |
| `<<` / `>>` | move left / right |
| Center | pause, or pick an upgrade |
| Spin the wheel | choose an upgrade |

Clear a room, pick 1 of 3 upgrades, and keep going. Every 5th room has a boss.

## How to put it on your iPod

1. **Back up your music**, just in case.
2. Download **Rockbox Utility** from https://www.rockbox.org/wiki/RockboxUtility and run it.
   Plug in your iPod and let it detect "iPod nano 2nd gen", then click **Install**.
3. Copy `pocket_slayer.lua` onto the iPod (any folder works, for example a new folder called `Games`).
4. Eject the iPod, reboot it into Rockbox, open **Files**, find `pocket_slayer.lua` and press Center to play.

## Make it your own

Open `pocket_slayer.lua` in any text editor. The **SETTINGS** section near the top has numbers you can change:

- `SHOOT_WHILE_MOVING = true` makes the game easier
- `START_HP` sets how much health you start with
- `PLAYER_SPEED` sets how fast you move

You can also add your own upgrades in the `UPGRADES` list.
