# Let's Go Recomp

Static recompilation of Pokémon Let's Go (Switch) to native PC code: a C runtime (`runtime/`) plus ~900 C files generated from the player's own game files (`generated/`, gitignored). Built on LAS Recomp (Zelda); runtime assumptions (formats, controller styles, return codes, reported resolution) may not hold for Let's Go — check there before blaming the game.

## Commands

Linux (Fedora/Debian, native):
```sh
python3 -m venv .venv
.venv/bin/pip install unicorn capstone lz4
make gen                      # extracted/exefs -> generated/
make -j$(nproc)               # build/lasrecomp + build/lasgame.so
./build/lasrecomp             # start screen
./build/lasrecomp extracted --play
```

Windows (MSYS2 UCRT64 on PATH):
```sh
make -j20 build/lasrecomp.exe
```

Fastest compile check (no game files needed; this is the CI gate):
```sh
make runtime-objs
```

Research/trace build:
```sh
make TRACE=1 B=build/trace GEN=generated-trace gen
make TRACE=1 B=build/trace GEN=generated-trace -j$(nproc) all
```

Release version comes from `RT_APP_VERSION` in `runtime/paths.h`. Release flow: `make deps-windows`, `make gen-helper`, `tools/fetch_zig.sh`, then `make dist`.

## Layout

- `runtime/` — C runtime: window, input, Vulkan renderer, system services, HLE, shared UI.
- `tools/` — Python generator (`gen.py`, `lifter.py`, `patches.py`) plus debug/research helpers.
- `docs/` — Portuguese documentation (`DEPURACAO.md`, `HISTORICO.md`, `PROGRESSO.md`, build guides).
- `third_party/` — vendored libraries (imgui, etc.).
- `generated/`, `extracted/`, `build/`, `save/`, `cache/`, `mods/` — gitignored; never commit. Game files and generated code must not enter the repo.

## Conventions

- Commits: Conventional Commits, English, imperative lowercase summary, no period. Types: `feat`, `fix`, `docs`, `perf`, `refactor`, `test`, `build`, `chore`. No `Co-Authored-By` / tool attribution.
- Documentation under `docs/` stays in Portuguese; commit messages, code comments, README in English.
- Line endings: LF (`.gitattributes`); `.bat`/`.ps1` are CRLF.
- Never commit Nintendo material: game files, keys, saves, mods, extracted/generated code, Switch system fonts (`.bfttf`).
- Parity: every feature works for both Eevee and Pikachu. Fixed addresses (60 fps, wild battles, generator patches) have per-build tables (`runtime/fnhook.c`, `tools/patches.py`, mapped with `tools/addrmap.py`); unknown builds get none.
- To change game behavior without rebuilding the game library, use function hooks in `runtime/fnhook.c`.
- Changing `runtime/cpu.h` or `runtime/gamelib.h` requires rebuilding the game library (`make -j`).
- Changing `GENARCH` requires deleting `build/obj/` first (objects do not track those flags).
- Woodpecker substitutes `${...}` across the whole `.woodpecker.yml`, including comments; read secrets as `$NAME`. CI runs `make runtime-objs` on Fedora and `sh -n tools/*.sh`.

## Verification

- No automated test suite. CI gate is `make runtime-objs`. Manual repro: `tools/repro.sh` (Windows-oriented).
- Debug variables and scripted input: `docs/DEPURACAO.md`. Fixed bugs are recorded in `docs/HISTORICO.md`; current state in `docs/PROGRESSO.md`.

## Gotchas

- On amdgpu, performance depends on huge pages for the guest window (the driver re-walks the imported userptr range); check `/proc/<pid>/smaps` before chasing frame-rate regressions. Other GPUs/drivers may not need it.
- System font substitute must be TrueType; do not use Noto Sans CJK (CFF outlines crash the font engine). Resolution order: `LARECOMP_FONT`, `fonts/` in data root, then common system paths.
- Data root resolution: `LARECOMP_DATA_ROOT`, then dev/portable mode, then OS default (`$XDG_DATA_HOME/lasrecomp` on Linux). The starting directory becomes the working directory after `rt_paths_init()`.
- `LARECOMP_DATA_ROOT` and `rt_remove_game_file` only touch `<data root>/extracted`; a symlinked `extracted/` is refused.
