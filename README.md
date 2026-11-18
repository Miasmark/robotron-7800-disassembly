# Robotron 2084 (Atari 7800) disassembly notes

An annotated disassembly project for *Robotron 2084* (NTSC, Atari, 1987; `Robotron 2084 (NTSC) (Atari) (1987) (CB22305D).a78`, 32K).

## How this was made, and how far to trust it

This is the output of **one automated research pass** on 2026-11-18: a single AI agent
session (Claude, working through the a7800-toolkit and MAME) given a list of questions and
about half an hour, not a long-running hand disassembly like
[galaga-7800-disassembly](https://github.com/Miasmark/galaga-7800-disassembly) and its
siblings. A second session then checked the report's main tables and routines against the
ROM's bytes; they matched. Nothing here was checked on a console.

Treat a **live** tag as "one agent saw this in MAME once", a **code** tag as a reading, and
the coverage figures below as what the tracer reached, not what was understood.

## Effort: a deep single-game pass

| | |
|---|---|
| Session | one agent, about 27 minutes, about 100 tool calls |
| Questions asked | the display lists under load; the object pool; collision with many objects; waves as data; cheap AI; the frame |
| Coverage | 6,501 instructions, 13,969 bytes of code (42.6% of the ROM); every other byte but 19 is in a declared data block. Round trip byte-identical. A 9,000-frame execute trace found no code outside the listing |
| Read closely | `$9003-$9CC6`, `$B000-$BDF1`, `$D000-$E5C7`, `$F86D-$F97F` |
| Skimmed or not read | the sound driver (skimmed); `$F3EA-$F86C` (title, options, High Score Cart, game over: not read) |
| Live checks | 19 run folders: write taps by raster line, cycle spans, forced budgets and zone counts, a death and restart |
| Not determined | quark, tank and shell timings (no tank wave was run); whether 28 objects really fit a line; PAL |

## What is here, and what is not

- `annotations.json`: entry points, labels, RAM names, data blocks and comments, in the
  [a7800-toolkit](https://github.com/Miasmark/a7800-toolkit)'s format.
- `docs/FINDINGS.md`: what the code does, with addresses, record formats and an evidence
  tag on every claim: **live** (watched in MAME: a tap, a trace, a RAM model, a poke that
  changed behaviour), **code** (read from the listing only), **hint** (a guess). Dead ends
  and corrections are kept in it.
- `tools/`: the probes and scripts the findings were made with.

**No ROM is here, and no listing.** A listing is the game's machine code in readable form;
it is rebuilt from `annotations.json` and your own legally owned dump with the toolkit's
`disasm.py`, and checked byte for byte with its `verify.py`. Captures, memory dumps,
renders of the graphics and traces are left out for the same reason.

## Running the tools

The scripts look for three things in the environment:

| Variable | What | Default |
|---|---|---|
| `A7800_ROMS` | the folder with your ROM dumps, named as below | `roms` |
| `A7800_TOOLKIT` | the a7800-toolkit's `tools` folder | `a7800-toolkit/tools` |
| `A7800_MAME` | a MAME with the Atari 7800 driver | `a78.exe` |

The live runs were made on [Miasmark/mame-Atari8bit7800](https://github.com/Miasmark/mame-Atari8bit7800),
windowless (`-video none -sound none -nothrottle`).

## Licence

MIT (see `LICENSE`) for the annotations, the findings and the tools. It does not cover the
games, which belong to their owners; nothing of theirs is distributed here.

## The session's own notes

Target: `Robotron 2084 (NTSC) (Atari) (1987) (CB22305D).a78` (32K, no banking, TIA, High
Score Cart). The cartridge is not in this folder's deliverables: `work/robotron.a78` is a
local copy the tools read. Nothing here is under git.

## Layout

| Path | What |
|---|---|
| `annotations.json` | the toolkit's annotations: entries, names, comments, data blocks |
| `tools/notes.py` | the same names as plain Python data; edit here, then run `tools/ann.py` |
| `tools/ann.py` | merges `notes.py` into `annotations.json`, re-disassembles to `work/src/rom.asm` and the narrow `work/c.txt` |
| `tools/compact.py` | makes the narrow listing |
| `tools/hx.py` | hex dump of the ROM or of a RAM dump at a CPU address |
| `tools/waves.py` | prints the 40 wave records and the difficulty and speed tables |
| `tools/run.py`, `tools/rb.lua` | one windowless MAME run in `work/runs/NAME` (inputs by frame, random play, pokes, holds, RAM dumps, per-frame peeks, PC hit counts with raster lines, execute coverage, PC-tagged read and write taps) |
| `tools/timing.lua` | scheduler, handler and drain timing per frame |
| `tools/spans.lua` | elapsed time of chosen routines (entry PC to exit PCs) |
| `tools/dlwrites.lua` | display-list writes by raster line |
| `tools/hitstats.py`, `tools/drainstats.py`, `tools/bill.py` | summaries of the runs' files; `bill.py` also prices a RAM dump's display with the toolkit's `zonebill.py` |
| `docs/` | `FINDINGS.md` |
| `work/` | generated listing, the simulator's trace (`work/sim`), every MAME run folder |

## Regenerating

    python -I tools/ann.py
    python -I ../../a7800-toolkit/tools/verify.py work/robotron.a78 -d work/src

Coverage as of 2026-11-18: 6,501 instructions, 13,969 bytes of code (42.6% of the ROM); all
other bytes but 19 are in declared data blocks; the round trip is byte-identical.

## Running MAME

`tools/run.py NAME KEY=VALUE ...` starts the fork (`mame-fork/a78.exe`)
with `-video none -sound none -nothrottle -bios skip`, its own `cfg`, `nv` and `snap`
folders and a `ui.ini` holding `skip_warnings 1`. The keys are in the header of
`tools/rb.lua`. Example, the wave-19 load run:

    python tools/run.py heavy1 "SCRIPT=200:-:-:0;10:-:-:1;290:-:-:0" RAND=3 END=3000 \
        "POKES=500:D5=12,C9=0" HOLD=C8=2 HOLDFROM=400 \
        HITS=9231,9139,920D,DEB7,DFFD,E351,E17B,E321,DEB9,91E5 DUMPS=900,1200

- `POKES=500:D5=12,C9=0` ends wave 1 and loads wave 19, but with wave 2's speeds. Add
  `6E=1B` for Intermediate's real wave-19 speeds, or `6E=44,73=46` for the hardest speed
  tables (runs `time_int19` and `time_max`).
- `HOLD=C8=2` keeps the player from ever being tested for a hit.
- For `timing.lua`, `spans.lua` and `dlwrites.lua` pass `--lua tools/NAME.lua` and
  `RBLUA=<absolute path of tools/rb.lua>`.

An execute tap (`EXEC=1`) runs at about 4 frames a second; everything else is fast.
