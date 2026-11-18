# Robotron 2084 (7800): findings

ROM: `Robotron 2084 (NTSC) (Atari) (1987) (CB22305D).a78`, 32K at `$8000-$FFFF`, no banking.
Addresses are CPU addresses; names are the ones in `annotations.json`.

Evidence tags: **(live)** watched in MAME (the user's fork, windowless; the run folder under
`work/runs/` is named), **(code)** read from the listing only, **(hint)** a guess.

All live runs use Intermediate difficulty. "Wave 19" runs force that wave by poking `Wave`
(`$D5`) = `$12` and `EnemiesLeft` (`$C9`) = 0 at frame 500, and most hold `PlayerHitDivider`
(`$C8`) at 2 so the player is never tested for a hit. Input is a random walk with a random
fire direction (`tools/rb.lua`, `RAND=3`), so the player keeps shooting and the wave thins.

## The short version

- The playfield lists are **never rebuilt**. Each object keeps the address of its own
  header(s). A move sets "edit" bits on the object and puts its slot number in a 34-entry
  queue. The queue is applied only between the bottom of the playfield (line 232) and its
  top (line 56). Insert is an append; delete moves the zone's last header into the hole.
  (code, live)
- Objects are run round-robin from a cursor. Each has a countdown decremented once per
  **pass of the scheduler**, not once per frame. The scheduler stops when 32 units of list
  edits are queued or when line 232 arrives, and carries on from the cursor next frame.
  Overload slows every enemy equally; the frame loop stays at 60 Hz. (live)
- A zone takes at most 23 enemies. A move that would bring a 24th in is **refused**: the
  object keeps its old row. Nothing flickers and nothing is dropped from a list. (live)
- With 79 objects and 131 headers on screen, 5 to 8 objects move per frame. At the hardest
  speed tables the scheduler fails to finish its pass in 29% of frames and the edit window
  is used up in 9%: the throttles are in real use at the top of the difficulty curve, and
  the game slows instead of tearing. (live)

## 0. Layout and coverage

| Range | What |
|---|---|
| `$8000-$9002` | graphics (even 4K block): title art |
| `$9003-$9CC6` | code: start, frame loop, scheduler, object handlers |
| `$9CC7-$9FFF` | unused, `$FF` (825 bytes) |
| `$A000-$AFFF` | graphics: sprites with page base `$A0`, character set at `$A800` |
| `$B000-$BDF1` | code: wave setup, more handlers, aiming and steering |
| `$BDF2-$BFFF` | unused, `$FF` (526 bytes) |
| `$C000-$CFFF` | graphics: sprites with page base `$C0` |
| `$D000-$E5C7` | code: wave end, death, score, NMI, shots, player, collision, list updater, sound |
| `$E5C8-$F31C` | tables: sound, handler addresses, steps, difficulty, speed, waves, zones, templates |
| `$F31D-$F97F` | code: reset, title, options, High Score Cart, demo autopilot |
| `$F988-$FC7F` | unused, `$FF` (760 bytes) |
| `$FC80-$FF06` | sprite tables |
| `$FF80-$FFFF` | signature, vectors |

Code sits in the odd 4K blocks and sprites in the even ones (`$A000`, `$C000`), so the
two-zone holey-DMA windows that reach 15 pages either side of the art land in blocks MARIA
reads as zero. (code; the playfield zones' DLL byte is `$4F`: 16 lines, 16K holes)

Coverage:
- The toolkit's tracer reaches 6,501 instructions, 13,969 bytes (42.6% of the ROM); every
  other byte but 19 is in a declared data block. `verify.py` passes (byte-identical).
- A 9,000-frame random-input run with an execute tap (`work/runs/exec1/exec.txt`) executed
  4,031 distinct instruction addresses. None lies outside the traced code. 2,470 traced
  instructions were not exercised by that run. (live)
- Read closely: `$9003-$9CC6`, `$B000-$BDF1`, `$D000-$E5C7`, `$F86D-$F97F`. Skimmed: the
  sound driver `$E395-$E5C7`. Not read: `$F3EA-$F86C` (title, options, High Score Cart,
  game over).

## 1. The display lists under load

### 1.1 Screen layout (live, `work/runs/t1`, `dlwalk.py` on a RAM dump)

DLL at `$1804`, written once by `BuildGameDll` (`$DC86`):

| Lines (MAME raster) | Zones | Lists |
|---|---|---|
| 16-39 | 2 blank | shared empty list `$1800` |
| 40-47, 48-55 | 2 of 8 lines | `$2253` score, `$226C` lives and wave: 5-byte character headers into `$2100-$2124` |
| 56-231 | 11 of 16 lines, DLL byte `$4F` | `$2280, $2300 ... $2780`: 128 bytes each (32 headers) |
| 232-258 | 3 blank | `$1800` |

DLI bits on the first playfield zone (NMI on line 56), the first blank zone below it (line
232) and the last zone (line 256).

An object up to 16 lines tall has one 4-byte header in the zone of its top line and, if it
straddles, a second in the next zone with the graphics high byte lowered by 16 (see the
skill `7800-maria-display-recipes`, "Per-pixel Y by writing an object into two zones").
`DlWriteHeader` (`$DE83`) writes: graphics low, palette+width, `ObjYTop - zone top + page
base`, `ObjXLeft`. (code)

### 1.2 What each object knows about its headers (code)

| Array | Meaning |
|---|---|
| `ObjHdrLo/Hi` `$1DDE/$1D87` | address of the header in the first zone |
| `ObjHdr2Offset` `$1E35` | one byte: second header = first + this. It fits because lists are 128 bytes apart and the second zone is always the next one |
| `ObjZones` `$1FE8` | low nibble first zone, high nibble second (0 = none), as the lists stand now |
| `ObjState` `$1F91` | bits 0-1 life (1 alive, +2 hit); bits 2-7 pending edits |

Per zone:

| Array | Meaning |
|---|---|
| `ZoneHeaderCount` `$2131,z` | headers in the list |
| `ZoneLastOwner` `$2125,z` | slot whose header is last |
| `ZoneOwners` `$194F + 32*z` | slot number per header position (the reverse index) |
| `ZoneEnemyCount` `$1963,z` | enemies booked into the zone (cap 23) |

### 1.3 Queueing a move: `DlQueueMove` (`$E1AF`) (code; costs live)

Handlers put the proposed box in `$BE-$C1` and call it before committing the position. It
compares the zones in `ObjZones` with the zones of the proposed top and bottom lines and
sets edit bits in `ObjState`:

| Bit | Edit | Work units |
|---|---|---|
| `$08` / `$04` | rewrite the header in the first / second zone in place | 1 |
| `$20` / `$10` | remove the header from the first / second zone | 2 |
| `$80` / `$40` | append a header to the new first / second zone | 1 |

- It clears the old edit bits first and works from `ObjZones`, so calling it twice before
  the edits are applied is safe.
- `DlEnqueue` (`$E339`) stores the slot in the ring `DlQueue` (`$2200`, 34 entries, head
  `$52`, tail `$53`) and adds the work units to `DlWorkPending` (`$50`). At `DlWorkBudget`
  (`$51` = 32) it sets `SchedStop` (`$54`).
- New objects use `DlQueueNew` (`$E136`).
- Cost (live, `work/runs/spans1`, 13,023 calls): mean 523 cycles of machine time, 388 when
  measured in blank lines, 132 at best.

### 1.4 The zone cap (live)

- For every type except the player (0) and type 15 (shots, the player's pieces), a move
  into a zone whose `ZoneEnemyCount` is already `$17` (23) is refused at `$E2CD`:
  `MoveRefused` (`$213E`) = 1 and the proposed Y is put back. Callers try once more with the
  old Y, so the X part still happens (`Obj_Grunt` `$947C`); humans and hulks pick a new
  direction instead (`$955D`, `$96C7`).
- A new object that would enter a full zone is not created (`$E17B`); spawners free the
  slot (`FreeSlotY` `$BAFB`). During the wave intro the enemy is deleted and `EnemiesLeft`
  decremented (`$DE1F`): the wave has one fewer.
- Natural play: 12 refusals in frames 850-3000 of `work/runs/heavy1`.
- Forced (`work/runs/zonefull`): holding zone 5's count at `$17` gave 253 refusals in 900
  frames and emptied that zone's list (15 headers down to 0-1) while its neighbours stayed
  populated.
- Why 23 (hint, from the toolkit's DMA model): 23 enemies + the player + 4 shots = 28
  two-byte objects is about 105 of the 108.6 cycles MARIA can spend on a line; 30 would pass
  it. Lists and owner tables hold 32, so 28 always fits.
- Counts can drift when an object is queued twice; `$E311` puts any negative count back to 0
  after every update.

### 1.5 Applying the edits: `DlDrain` (`$DEAA`) (live)

- Waits for `LogicWindow` (`$E4`) = 0, which the line-232 interrupt sets, then takes slots
  from the queue until it is empty or `LogicWindow` is 1 again (the line-56 interrupt).
- Remove (`DlRemoveHeader` `$E005`): copy the zone's last header into the hole, repoint the
  moved header's owner, zero the vacated header's second byte, fix the owner table. That
  zero is the terminator: appends never write one, because the unused part of a list is
  kept zero.
- Append (`DlAppendHeader` `$DE54`): header index = `ZoneHeaderCount`; record the owner.
- At exit it sets `LogicWindow` = 1 itself (`$DFFD`), so objects run during the rest of the
  blank, not only from line 56.
- One frame (`work/runs/heavy2`, `work/runs/time1`):

  | Raster line | What |
  |---|---|
  | 232 | NMI: `LogicWindow` = 0, frame counter + 1, sound tick |
  | 234-249 | drain starts |
  | 254 to about line 50 of the next frame | drain ends (cut at lines 56-63) |
  | then | `MainLoop`: timers, switches, colour cycle, shots, player, `RunObjects` |
  | until 232 | when the pass is done, idle spin at `$920D` |

- Per item: 600-640 cycles, 1.6 header writes. Per part (`work/runs/spans1`, means): header
  write 79, sprite lookup `SpriteFor` 103, append 162, remove 347.
- The window from line 236 to line 56 is 83 lines, about 9,400 cycles: 15-18 items.
- Writes to the lists by raster line (`work/runs/dlw`, 95,590 writes in 2,150 frames):
  56,049 on lines 232-262, 38,637 on lines 0-55, 904 on lines 56-231. Of the 904, about 135
  are the item in progress finishing on lines 56-63; the rest belong to the one list clear
  at the wave change (`$DCA1`). So a header in the top zone can, rarely, be rewritten while
  it is drawn.

### 1.6 What bounds the frame (live)

1. The edit budget: 32 work units queued stop the scheduler for the frame.
2. The beam: the scheduler stops at line 232 wherever it is; the drain stops at line 56.
3. Pass-counted timers (section 2) turn any shortfall into uniform slowdown.
4. Step rates: a grunt's period is 32 down to 9 passes by speed index, plus or minus 3,
   and falls by 1 every 128 frames to a floor of 3.

Load in three cases, all with wave 19's 66 grunts, 9 humans, 3 hulks, 4 spheroids:

| | Wave-2 speeds (index 11), frames 850-1500 | Intermediate's wave-19 speeds (index 28), first 150 frames | Hardest tables (index 69), first 150 frames |
|---|---|---|---|
| run | `time1`, `heavy1` | `time_int19` | `time_max` |
| handler dispatches a frame, mean (max) | 5.05 (13) | 5.8 (12) | 8.4 (15) |
| queue items a drain, mean (max) | 6.4 (15) | 7.4 (14) | 9.5 (15) |
| drain cycles, mean (max) | 3,919 (9,907) | 4,628 (8,991) | 6,098 (9,972) |
| frames with no idle spin (pass not finished) | 15 of 651 | 11 of 151 | 44 of 151 |
| drains cut at line 56 (with work left) | 4 (0) | 0 | 13 (6) |
| frames that hit the edit budget | 1 | 0 | 4 |

Forcing it (`work/runs/budget4`): with `DlWorkBudget` held at 4, dispatches fell from 5.05
to 0.88 a frame, slot visits from 83 to 10.8 a frame (a pass took about 8 frames), the idle
spin vanished, and `MainLoop` still ran once per frame with an intact picture.

Where a frame goes in the first case (means; rows overlap a little because handler and shot
times include DMA halts):

| Item | Cycles |
|---|---|
| MARIA DMA: 79 objects, 131 playfield headers, 524 list bytes (`bill.py` on `heavy1` frame 900) | about 8,700 (29%) |
| drain | 3,900 |
| scheduler scan: 82 slots at about 51 cycles (counted from the listing) | 4,200 |
| handlers: 5.05 dispatches at about 925 | 4,700 |
| shots | 1,800 |
| player | 1,100 |
| idle spin: 827 turns of 9 cycles | 7,400 |

`MainLoop` runs once per frame. Nothing is at 30 Hz, though the player moves every second
frame and is tested for hits every third.

## 2. The object pool

### 2.1 Arrays (code)

87 slots, 16 arrays of `$57` bytes from `$1ACF` to `$203E` (1,392 bytes):

| Array | Use |
|---|---|
| `ObjXLeft $1ACF`, `ObjXRight $1EE3`, `ObjYTop $1B26`, `ObjYBottom $1F3A` | the box, all four edges stored |
| `ObjTimer $1B7D` | passes until the handler runs |
| `ObjDir $1BD4` | direction 0-7, or packed X velocity |
| `ObjVarA $1C2B` | target slot, packed Y velocity, counters |
| `ObjVarB $1C82` | steps until the next decision |
| `ObjFrame $1CD9` | animation frame |
| `ObjVarC_FreeLink $1D30` | per-type; the free-list link while free |
| `ObjHdrHi $1D87`, `ObjHdrLo $1DDE`, `ObjHdr2Offset $1E35`, `ObjZones $1FE8` | section 1.2 |
| `ObjType $1E8C` | bits 0-4 type, bits 5-7 an enforcer's fire-timer index |
| `ObjState $1F91` | bits 0-1 life, bits 2-7 pending list edits |

Slot 0 is the player. Slots `$53-$56` are the four shots (type 15), addressed as `array +
$53,X` (`$1B22`, `$1B79`, `$1C27`...). Slots 1-`$52` (82) are everything else.

Types: 1 grunt, 2 mommy, 3 daddy, 4 mikey, 5 hulk, 6 spheroid, 7 quark, 8 enforcer, 9 tank,
10 brain, 11 prog, 12 enforcer spark, 13 cruise missile, 14 tank shell, 15 shot or player
piece, 16 electrode. (code: named from the wave table's counts and each handler's
behaviour; sprites were not matched one by one)

### 2.2 Partition and allocation (code)

- `SpawnWave` (`$B054`) fills slots in class order and leaves the range starts in zero
  page: grunts from 1, electrodes from `SlotElectrodes` (`$DF`), humans `$D6`, hulks `$D7`,
  spheroids `$D8`, quarks `$D9`, tanks, brains `$DC`.
- The rest, up to `$52`, is chained into a free list through `ObjVarC_FreeLink`, head
  `FreeListHead` (`$EF`), `$80` = end (`$B463`).
- `AllocSlot` (`$9234`) pops the head. It fails when the list is empty, and also when the
  head's `ObjState` is not 0: a slot freed this frame still has its "remove" bits set until
  the drain has taken its headers out, so it is not reused under a stale header.
- `FreeSlot` (`$D71E`) pushes the slot, queues the removal, clears the type. All slots
  return to the one free list.
- Spawns that find no slot are dropped. Waves 19, 29 and 39 fill all 82 slots at the start
  (`tools/waves.py`).

### 2.3 The scheduler: `RunObjects` (`$91E3`) (live)

- Visits slots from `SchedCursor` (`$55`), wrapping at `$53` to 1. Skips empty slots, the
  class being brought in by the wave intro, and objects not yet in a list.
- `DEC ObjTimer,X`; at -1 the handler runs (`JMP ($A0)` at `$9231`, table `$EBE5`) and
  returns to `ObjDone` (`$91FC`) having set its next timer.
- After each slot: stop if `SchedStop` is set or `LogicWindow` is 0.
- When the cursor is back where the pass began it spins until the frame counter changes
  (`$920D`): at most one pass per frame.
- A sleeping live slot costs about 51 cycles to visit (counted from the listing): 4,200 a
  frame for 82 slots, 14% of the frame spent decrementing timers.

Timer reload by class, in passes (code; grunt ramp live in `work/runs/cc`):

| Class | Reload |
|---|---|
| grunt | `GruntPeriod` (`$CC`) + random -3..+3; `$CC` from table `$ED76`, less 2 on a restarted wave, less 1 every 128 frames of play, floor 3 |
| human | 10 |
| hulk | `HulkPeriod` `$CE` (22 down to 7 by speed index) |
| spheroid | `SpheroidPeriod` `$CF` (6 down to 3) |
| quark, tank, cruise missile | 3 |
| enforcer, shell | 2-9 from `AimAt`: shorter when far from the target |
| brain | `BrainPeriod` `$D2` (15 down to 6) |
| prog | 4 |
| spark | frame / 8 |
| electrode | `$7F` (sleeps until hit) |

First timers are staggered by slot (`$B0A7`: 8 + slot AND 15).

Not on the scheduler: `RunPlayer` (`$D79E`) moves the player every second frame (1 pixel, 2
lines); `RunShots` (`$D733`) moves each shot 4 pixels and 8 lines every frame, and each live
shot queues a list edit every frame.

## 3. Collision

All tests are box tests on the four stored edges; no widths are added at test time.

| Test | Where | How often | Narrowing |
|---|---|---|---|
| shot v. everything | `ShotCollide` `$D9AA` | every frame, per live shot | `ZoneOwners` of the shot's one or two zones |
| player v. everything | `PlayerCollide` `$D806` | every third frame | `ZoneOwners` of the player's zones |
| grunt v. electrodes | `Obj_Grunt` `$93B0` | when that grunt steps | slots `SlotElectrodes..SlotHumans` |
| human v. hulks | `Obj_Human` `$94B6` | when that human steps | slots `SlotHulks..SlotSpheroids` |
| hulk v. electrodes | `Obj_Hulk` `$95D2` | when that hulk steps | electrode range |
| brain v. its human | `Obj_Brain` `$9B01` | every fourth brain step | one target slot; `DirToward` returning "touching" is the test |

- **The owner tables as cells** (live): `$D839` and `$D9E8` walk 28 owner entries (one zone)
  or 56 (two: the next zone's table follows in memory) and box-test the slots found. A read
  tap on `$194F-$1ACE` (`work/runs/own1`) names these two loops and the remove routine as
  the readers.
- **It is not cheap** (live, `work/runs/spans1`): a live shot costs 605 to 4,636 cycles a
  frame, mean 1,536; `RunShots` averages 1,830 a frame with shots in flight and peaked at
  10,956. The loop always walks all 28 or 56 entries (16 cycles for an empty one). At 70
  enemies a shot looked at 36 entries and made 8 box tests per frame on average
  (`work/runs/own2`). `PlayerCollide` averaged 2,204 (`work/runs/spans2`, 15 samples only).
- **Tests at the mover's own cadence** (live): enemy-against-enemy box tests average 1.6 a
  frame in wave 19 (`work/runs/own2`). `BoxOverlapXY` (`$DC5D`) takes 16 cycles when the
  first compare rejects, 30 on average, Y first.
- **A forgiving hit on the player** (code): after the boxes overlap, `PlayerTouchDepth`
  (`$DC13`) counts a hit only if the overlap is at least 7 lines deep, or at least 4 pixels
  wide, or 8 together. Humans are collected on plain overlap.
- **Per-target hit cooldown** (code): a hulk takes a shot's push only if 8 frames have
  passed since the last (`$DA91`: frame counter minus a stamp in `ObjVarA`).
- A cruise missile is hit only at its head, a point from two nibbles in `ObjVarC` (`$DA0C`).
- Spawn placement reuses the box test: electrodes retry until they overlap no earlier
  object (`$B11D`), humans until they overlap no electrode (`$B1CB`). (code)

## 4. Waves as data

- **Record**: 16 bytes at `$EF1A + 16*(wave-1)`, 40 waves, copied to `WaveRecord`
  (`$1906`): grunts, mommies, daddies, mikeys, hulks, spheroids, quarks, enforcer limit
  (always 8), tanks, brains, four unused, electrode shape, electrodes. `tools/waves.py`
  prints them. (code; wave 1's 15 grunts and 5 electrodes live)
- **Wrap**: `NextWave` (`$B000`) subtracts 20 while the wave number is 41 or more, so waves
  21-40 repeat. (code)
- **Speed is a separate cursor**: `SpeedIndex` (`$6E`) indexes six 70-byte tables at
  `$ED76` (grunt period, hulk period, hulk tracking, spheroid spawn delay, spheroid period,
  brain period). It starts at 0, 10, 20, 30 or 20 by difficulty (`$ED6C`), rises 1 per wave,
  and on reaching start + 40 drops back 20: a sawtooth over the last 20 entries. Difficulty
  also sets lives (5, 5, 3, 3, 1), the enforcer fire reload and a spawn chance base
  (`$ED62-$ED75`). (code; `SpeedIndex` = `$0A` and `GruntPeriod` = `$1A` live)
- **Within a wave** (`WaveTimers` `$9155`): every 128 frames grunts get 1 faster, brains may
  fire again, and the spawn chance for enforcers and tanks rises; every 64 frames the
  spheroids' first-spawn delay counts down. (code; grunt ramp live)
- **Placement**: `RandomSpotAwayFromCentre` (`$D3D8`) redraws until the point is outside the
  box X `$28-$6A`, Y `$40-$7F` around the player's start. Spheroids start on the left or
  right edge and quarks on the top or bottom edge, by slot parity. (code)
- **Intro**: `WaveIntro` (`$9248`) brings classes in in the order of `$ED44` (humans,
  brains, electrodes, quarks, spheroids, grunts, tanks, hulks), one object every second
  frame through the same edit queue, with the game frozen (`IntroFreeze` `$E2`). (code)
- **Death keeps the survivors** (live, `work/runs/death`): `PlayerDied` (`$D011`) zeroes the
  record, counts the live objects of each class back into it (`$D0A1`), and the same spawner
  runs again. Seen: 15 grunts and 5 electrodes respawned as 15 and 5; after two grunts died
  on electrodes, 13 and 3.
- Extra life every 25,000 points, checked at the end of the score add (`CheckExtraLife`
  `$D487`); none on the hardest difficulty. (code)

## 5. Enemy behaviour

Sizes are the handlers' byte lengths; times are means of machine time from dispatch to
return, DMA halts and the `DlQueueMove` call included (`work/runs/time1`).

| Class | Handler, bytes | Mean cycles | Rule |
|---|---|---|---|
| grunt | `$9391`, 271 | 925 | 2 pixels and 4 lines toward the player on both axes every step; a wall cancels that axis |
| human | `$94A0`, 294 | 1,220-1,310 | one of 8 directions held for 10-41 steps; new direction at a wall or a full zone |
| hulk | `$95C6`, 306 | 846 | 4 directions; every 0-15 steps either `DirToward` the player (when the speed table's tracking byte is set) or random; a shot pushes it 3 steps |
| spheroid | `$96F8`, 300 | 1,140 | velocity and acceleration packed per axis, clamp at 5, new random acceleration every 0-7 steps |
| quark | `$9824`, 307 | not run | diagonal moves; spawns a tank when a 6-bit random is under `SpawnChance` |
| enforcer | `$9957`, 323 | 940 | `AimAt` the player, 1 time in 16 a random drift; fires from its own timer |
| brain | `$9A9A`, 483 | 717 | `DirToward` a target human; on touch turns it into a prog; fires a missile every 3-130 steps |
| prog | `$B740`, 269 | 1,076 | 4 directions, mostly toward the player |
| spark | `$B647`, 249 | 960 | packed velocity with acceleration, 32-step life |
| cruise missile | `$B84D`, 308 | 1,070 | 8 directions toward the player, may not reverse (`$EC94`) |
| tank | `$B4C7`, 247 | not run | 6 of 8 directions for 0-31 steps; a shell every 15 steps, at most 11 shells |
| shell | `$BB0D`, 149 | not run | straight, reflects off walls, 36-step life |
| electrode | `$9C7D`, 74 | 268 | none |

Shared pieces:
- `DirToward` (`$BD6E`, 132 bytes, mean 161 cycles): compares box edges and builds a stick
  nibble in SWCHA's own format (`$0F` = touching), then maps it to a direction through
  `$EC05`. With `$B7` set, a diagonal keeps one axis at random. (code; timing live)
- `AimAt` (`$BCDC`, 146 bytes, mean 371 cycles): takes |dx| and |dy| to a point, halves both
  together until each is under 9 (or 5), restores the signs. It also returns 10 minus the
  bit length of the mean distance, used as a timer reload. (code; timing live)
- `PackVelAccel` / `UnpackVelAccel` (`$BA03` / `$BA28`): 5 bits of signed velocity and 3 of
  signed acceleration in one byte per axis. (code)
- `Random` (`$D3A8`, 38 cycles): frame counter + two state bytes - `NmiStackSample`, with
  whatever carry comes in. The NMI reads `NmiStackSample` from below the stack pointer
  (`TSX / DEX / LDA $0100,X` at `$D56F`), a stale byte that depends on what code ran last.
  (code; the write at `$D574` live) That the `DEX` was meant to reach the return address is
  a guess. (hint)
- The demo's autopilot (`Demo_MoveStick` `$F903`, `Demo_FireStick` `$F8BB`) feeds
  `DirToward`'s result into the player's own stick path: away from the nearest threat inside
  a 19 by 32 box (opposite-direction table `$F980`), otherwise toward a human. (code)

## 6. Frame architecture, input, the rest

- **NMI** (`$D56B`): saves A and X in zero page and `JMP ($59)`. Three stages, each arming
  the next: line 56 `Nmi_PlayfieldTop` (`$D5B1`: palette 7 for the playfield, `LogicWindow`
  = 1), line 232 `Nmi_PlayfieldBottom` (`$D57E`: palette 7 for the HUD, `LogicWindow` = 0, a
  call to `Random`, frame counters, `SoundTick`), line 256 `Nmi_VblankResync` (`$D5D2`:
  three WSYNCs, reads MSTAT until two reads agree, re-arms the first stage only if vblank is
  set). Lines live (`work/runs/heavy2`). Same shape as the skill `7800-frame-architecture`,
  "Each handler arms the next" and "Resync at the chain's foot".
- **Single buffer, no flip**: logic runs while the picture is drawn and only queues; the
  lists change in the blank.
- **Input** (code): the first stick moves (`$D7B1`, SWCHA high nibble), the second fires
  (`ReadFireStick` `$D947`, low nibble). If the second is centred and the first button is
  down, the shot goes where the first stick points, so one stick works with no option to
  set. One shot per 8 frames, 4 in flight.
- **Colour cycling** (`CycleColours` `$D35D`): one counter drives five palette registers
  three frames out of four. (code)
- **Death**: `PlayerDied` ramps palette 0 for about 215 frames with the game stopped. (live:
  `MainLoop` absent for frames 563-777 in `work/runs/cc3`)
- **Sound** (skimmed, code): 21 effects on TIA's two voices. Per effect a priority
  (`$E646`), a tick period (`$E65B`), an optional partner effect for the other voice
  (`$E670`) and three parallel streams (frequency, with commands `$FF` end, `$FE` new
  priority, `$FD` chain; control; volume). A request takes a free voice or the one with the
  lower priority. Not compared with the `7800-sound-drivers` skill.

## Dead ends and corrections

- **The first wave-19 load runs used wave 2's speeds.** Poking the wave number does not move
  `SpeedIndex`. Those runs (`heavy1`, `time1`) showed a quarter of the frame idle and almost
  no throttling, and I first concluded the throttles were rarely needed. With the real
  speed indexes poked (`time_int19`, `time_max`) they are in use: see the table in 1.6.
- **Expected: the zone tables make shot collision cheap.** Measured, a shot costs about
  1,500 cycles a frame at this density, the same order as a plain loop over 82 slots with a
  Y reject.
- **The execute trace added nothing.** The tracer already had all the code; the trace's use
  was as a check.
- **A read tap on the owner tables named a dozen wrong readers.** `LDA abs,X` that crosses a
  page reads `address - $100` first, and taps see that dummy read. Likewise a write tap
  counts an `INC` twice.
- **"The grunt ramp stops after two steps"** was the death sequence: the scripted player
  stood still, died at frame 562, and `WaveTimers` does not run during the flash.
- **A collision count run without the invulnerability hold** (`work/runs/own1`) spent most
  of its time in death sequences; redone as `own2`.
- **`$E4` first named "beam in playfield".** The drain sets it to 1 itself when it finishes,
  so it is a "logic may run" flag: `LogicWindow`.
- **Wave "0"** in a naive dump of the wave table is the tail of the speed tables; records
  start at wave 1 (`$EF1A`).
- `dlwalk.py --zones 20` shows two "zones" after line 258; they are the bytes after the DLL.
- `simprobe.py --explore` (3,000 simulated frames) reached 4,830 instructions and ten
  indirect jumps, all already in the listing.

## Not determined

- `$F3EA-$F86C`: title, option select, High Score Cart calls, game over.
- Wave record bytes 10-13 are zero in all 40 waves; whether any code reads them.
- Timings of the quark, tank and shell handlers: no tank wave was run.
- Whether 28 two-byte objects really stay under MARIA's line limit (model figure).
- Whether a header rewritten on lines 56-63 ever shows as a glitch.
- The sprite tables at `$FC80` were used, not decoded frame by frame.
- Load with a player who shoots less than the random script does (the waves thinned fast).
- PAL: no PAL image was looked at.
