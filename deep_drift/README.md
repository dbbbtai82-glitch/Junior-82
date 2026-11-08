# Deep Drift (PS Vita homebrew)

A small, original underwater survival game. Your boat sank! Dive down, collect
**10 scrap** to build a raft, and get back to the surface before your oxygen runs out.
Watch out for the red fish.

## Controls
| Button | Action |
|---|---|
| Left stick / D-pad | Swim |
| START | Restart after you win or lose |
| SELECT | Quit |

## How to build
1. Install [VitaSDK](https://vitasdk.org) (it includes vita2d).
2. Run these commands from this folder:
   ```
   mkdir build && cd build
   cmake ..
   make
   ```
3. Copy `deepdrift.vpk` to your hacked Vita and install it with **VitaShell**.

## Easy things to change in `main.c`
- `SCRAP_TO_WIN`: how much scrap you need to win
- `NUM_FISH`: more fish makes it harder
- `PLAYER_SPEED`: how fast you swim
- The oxygen numbers in `update()`: how fast your air runs out
