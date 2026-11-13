# Chess Circuit — a chess game for KOReader

A complete, fully offline chess game for e-readers running [KOReader](https://github.com/koreader/koreader),
designed for the colour e-ink screen of the Kobo Libra Colour (it also works in black and white).

The game is available in two languages, in two separate plugin folders:

| Language | Folder | Name in KOReader | Save file |
|---|---|---|---|
| English | [`english/chesscircuit.koplugin`](english/chesscircuit.koplugin) | Tools → **Chess Circuit** | `koreader/settings/chesscircuit.lua` |
| French | [`french/chesscoach.koplugin`](french/chesscoach.koplugin) | Tools → **Le Circuit (échecs)** | `koreader/settings/chesscoach.lua` |

The French version is the most recent one: on top of everything below, it has **5334 puzzles**,
**mistake training**, a **two-player mode**, **online play on Lichess**, **board themes** and a new
**human-like AI** (see [What's new in the French version](#whats-new-in-the-french-version)).
The English version has not been updated yet. The two versions use different folder and save-file
names, so both can be installed side by side (the French version also uses French piece letters: R, D, T, F, C).

It bundles the Stockfish engine and adds three ways to play:

- **Coach**: play against an AI from 400 to 2500 Elo, in five playing styles. Tap the light bulb whenever you want
  the coach's opinion. Each move gets a chess.com-style verdict (brilliant, great, best, excellent, good,
  inaccuracy, mistake, miss, blunder) with coloured arrows and a plain-language explanation of what the move does (in English or French).
- **Tournaments**: a season-long circuit of 10 tournaments in 10 capitals, with made-up opponents who play like humans.
- **Casual games**: blitz 3 + 5, rapid 10 + 5 or no clock.

| | | |
|---|---|---|
| ![Main menu](screenshots/main_menu.png) | ![Capitals circuit](screenshots/capitals_circuit.png) | ![Tournament game](screenshots/tournament_game.png) |
| ![Coach](screenshots/coach.png) | ![Game summary](screenshots/game_summary.png) | ![Trophy shelf](screenshots/trophy_shelf.png) |

French version:

| | | |
|---|---|---|
| ![Menu principal](screenshots/fr_main_menu.png) | ![Coach](screenshots/fr_coach.png) | ![Étagère des trophées](screenshots/fr_trophy_shelf.png) |

## What's new in the French version

| | | |
|---|---|---|
| ![Menu](screenshots/fr_menu.png) | ![Problems](screenshots/fr_problemes.png) | ![A problem](screenshots/fr_probleme.png) |
| ![Board themes](screenshots/fr_themes.png) | ![Two-player duel](screenshots/fr_duel.png) | ![Online on Lichess](screenshots/fr_en_ligne.png) |

- **Problems**: the 5334 positions of László Polgár's *Chess: 5334 Problems, Combinations and Games*
  (mates in 1, 2 and 3, combinations, miniature games, endgames), in 10 chapters, with progress, streaks,
  hints and solutions. Another move than the book's is accepted if Stockfish confirms it mates just as fast.
  This public version contains the positions and the solutions only, not the book's commentary.
- **Mistakes to rework**: the coach scans your finished games and turns your mistakes, misses and blunders
  into exercises (find the better move from the position just before), then lets you play on against the AI from there.
- **Replay from any position**: while reviewing a game, play on against the AI from the position on screen (unrated).
- **Duel local**: two players face to face on the same reader, with 3+2, 5+5, 10+5 or 15+10 clocks.
  The pieces turn to face the player whose turn it is (or stay fixed, the far side upside down).
- **Online on Lichess** ("En ligne"): play real opponents on lichess.org with this app's board and clock, through
  Lichess's official Board API (rapid and classical time controls, rated or casual). It needs Wi-Fi and a personal
  Lichess API token with the "Play games with the board API" permission, saved in `koreader/settings/lichess_token.txt`
  or typed in the app. Your password is never used. The coach and Stockfish are switched off during online games, as Lichess requires.
- **Board themes**: grey, green, wood, blue, ice, purple, coral, sand and slate.
- **Human-like AI**: Stockfish proposes its 10 best moves, and a model trained on 36,000 positions from real
  Lichess games (six rating bands, 400 to 2400) gives each move the probability that a human of that level plays it,
  from what the move costs and what a human notices (captures, checks, recaptures, castling, development, threats,
  hanging pieces…). On held-out positions it predicts the move the human actually played 44–50 % of the time
  (Stockfish's top move alone: 35–44 %). Openings come from a book of the moves real players of each level play.
  Displayed ratings follow the chess.com scale.

## Features

### Requirements

- An e-reader running KOReader. It was designed for the **Kobo Libra Colour**; other Kobo devices with an ARM processor should work.
  Colours are pastel on colour screens and switch to shades of grey on black and white screens.
- Nothing else: no internet connection, no account. Everything runs on the device
  (only the optional online mode of the French version uses Wi-Fi and a Lichess account).

### Coach mode
- The board stays clean while you play; nothing pops up after your moves.
- Tap the **light bulb** to see your last move's verdict, an arrow for your move, a green arrow for the best move,
  and an explanation: development, centre control, open lines, threats, forks, pins, hanging pieces,
  the opponent's best reply and the idea behind the best move.
- **‹ ›** (or the reader's page-turn buttons, or a swipe) step back and forth through the game, including the AI's moves.
  Replay the same move and the AI answers exactly as before; play a different move to branch off from there.
- **Eval** shows or hides a horizontal evaluation bar under the board.
- **Hint** gives a discreet hint first, then the move.
- **Analyse a past game**: any finished game from any mode can be reopened in the coach for a move-by-move review.

### Tournaments
- 10 opens (Brussels, Paris, London, Madrid, Rome, Berlin, Budapest, Reykjavik, Buenos Aires, Tokyo):
  8 players, 6 Swiss-system rounds, 10 + 5, standings between rounds. Each city has its own trophy.
- Around 150 made-up circuit players close to your rating, each with a personality (attacker, positional, solid,
  tactician, deep thinker, blitzer, balanced). They think at a human pace, play worse when short of time
  and in faster time controls, may accept draws, and resign lost positions.
- Real chess clocks with increment, draw offers and resignation. No coach and no takebacks.
- **Premoves**: while the opponent is thinking, tap one of your pieces and then a target square. Both squares turn blue
  and the move is played as soon as the opponent has moved, if it is still legal. Tap elsewhere to cancel.
- A real-time season of 365 days, starting with your first tournament. You have 10 months to win all 10 trophies.
  If you do, the **Candidates Tournament** unlocks (6 rounds, 15 + 10, slightly stronger field).
  On day 364 comes the **World Championship**: a 13-game match against the reigning champion.
- Progress, clocks and games are saved, so you can stop at any time and resume later.

### After each game
- A summary screen with the result, your Elo change, accuracy (coach games) and an advantage graph
  (white area up when White is better, black area down when Black is better). Tap the graph to jump to that moment.
- Your Elo rating goes up and down after every rated game. The profile screen shows its history.

## Installation

1. Download this repository (green **Code** button → **Download ZIP**) and unzip it.
2. Connect the e-reader to your computer with a USB cable.
3. Copy the plugin folder of your language to `koreader/plugins/` on the device
   (on Kobo the folder is hidden: `.adds/koreader/plugins/`):
   - English: `english/chesscircuit.koplugin`
   - French: `french/chesscoach.koplugin`
4. Eject the reader safely and restart KOReader.
5. Open the top menu → **Tools** → **Chess Circuit** (or **Le Circuit (échecs)**).

To update, replace the plugin folder with the new one. Your rating, history and season progress are kept,
because they live in the save file, not in the plugin folder.

## Tips

- The reader's **page-turn buttons** step through the game (back / forward) in coach mode and when reviewing finished games.
- A long press on **‹** or **›** jumps to the start or the end of the game.
- In coach mode, the AI level (400–2500 Elo), its style and the analysis time are in **Menu**.
  A longer analysis time gives a more accurate coach but uses more battery.
- Coach games in which you took moves back are not rated.

## About the engine

The `bin/stockfish` file inside each plugin folder is **Stockfish 11** (GPL v3, <https://github.com/official-stockfish/Stockfish>, tag `sf_11`),
statically cross-compiled for 32-bit ARM (armv7, hard-float), which runs on Kobo devices.
It includes one small patch (`bin/stockfish_patch.diff`) that lets a search finish when its input ends.
Stockfish 11 was chosen because it needs no neural-network file and is light enough for an e-reader.

To rebuild it yourself:

```sh
git clone --depth 1 --branch sf_11 https://github.com/official-stockfish/Stockfish.git
cd Stockfish && git apply ../english/chesscircuit.koplugin/bin/stockfish_patch.diff && cd src
make build ARCH=armv7 COMP=gcc CXX=arm-linux-gnueabihf-g++ EXTRALDFLAGS="-static"
arm-linux-gnueabihf-strip stockfish
```

On other devices (for example an x86 Linux build of KOReader), replace `bin/stockfish` with a Stockfish binary built for that platform.

## How it works

Everything is plain Lua on top of KOReader's widgets, with no extra libraries.
The two folders contain the same files:

| File | Role |
|---|---|
| `cc_chess.lua` | Chess rules, move generation (perft-verified), SAN notation |
| `cc_engine.lua` | Runs Stockfish in the background without freezing the screen |
| `cc_ai.lua` | Level-based move choice, playing styles, human-like personalities, thinking times and time-pressure stress |
| `cc_coach.lua` | Move classification and plain-English explanations |
| `cc_match.lua` | A game in any mode: navigation, takebacks, clocks, premoves, draw offers, analysis |
| `cc_tournament.lua`, `cc_career.lua`, `cc_names.lua` | Swiss pairings, season calendar, circuit players |
| `cc_screen.lua`, `cc_menus.lua`, `cc_ui.lua`, `cc_board.lua`, `cc_art.lua`, `cc_draw.lua`, `cc_lamp.lua` | Screens and hand-drawn graphics |
| `cc_app.lua`, `main.lua` | Glue code and KOReader plugin entry point |

The French version adds:

| File | Role |
|---|---|
| `cc_model.lua`, `cc_model_w.lua` | Human move model and its trained weights |
| `cc_book.lua`, `cc_human.lua` | Opening book and clock-use statistics from Lichess games |
| `cc_problems.lua`, `cc_problems_data.lua` | Problems section and its 5334 positions |
| `cc_mistakes.lua` | Exercises built from your own mistakes |
| `cc_duel.lua` | Two-player mode on one reader |
| `cc_lichess.lua` | Online play through the Lichess Board API |

The training data for the AI comes from the [Lichess](https://lichess.org) game database (games are public domain, CC0).
All players and their names are made up. Any resemblance to real people is coincidental.

## License

GPL-3.0, see [LICENSE](LICENSE). The bundled Stockfish binary is also GPL-3.0.
