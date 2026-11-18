-- timing.lua: rb.lua plus elapsed-time measurements between chosen PCs (machine time, so DMA
-- halts are included; 1 unit = one 1.79 MHz CPU cycle). Frames TFROM..TTO only.
--   handler.txt   per object type: dispatches, mean/max cycles from the dispatch ($9231) to the
--                 handler's return to the scheduler ($91FC)
--   drain.txt     per frame: line the drain starts ($DEB7) and ends ($DFFD), cycles, queue
--                 items ($DEB9), header writes ($DE83), removals ($E005), inserts ($DE54)
--   sched.txt     per frame: scheduler entry line ($91E3), first idle spin line ($920D), slots
--                 scanned ($91E5), dispatches, budget hits ($E351), stop by beam (pass unfinished)
dofile(os.getenv("RBLUA"))
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local scr
for _, s in pairs(M.screens) do scr = s break end
local CPS = 1789772.5
local TFROM = tonumber(os.getenv("TFROM") or "0")
local TTO = tonumber(os.getenv("TTO") or "99999999")
local fr = 0
local function now() return M.time:as_double() * CPS end
local function line()
  local lines = scr.frame_period / scr.scan_period
  local left = scr:time_until_pos(0, 0) / scr.scan_period
  return math.floor((lines - left) % lines)
end
local function on(a, fn)
  return mem:install_read_tap(a, a, "t" .. a, function(a2, d)
    if cpu.state["PC"].value == a and fr >= TFROM and fr <= TTO then fn() end
    return d
  end)
end

-- handlers
local ht, hn, hsum, hmax = nil, {}, {}, {}
local htype = 0
local disp, scan, budget = 0, 0, 0
local s_in, s_idle = nil, nil
T1 = on(0x9231, function()
  ht = now()
  htype = mem:read_u8(0x1E8C + cpu.state["X"].value) & 0x1F
  disp = disp + 1
end)
T2 = on(0x91FC, function()
  if ht then
    local d = now() - ht
    hn[htype] = (hn[htype] or 0) + 1
    hsum[htype] = (hsum[htype] or 0) + d
    if d > (hmax[htype] or 0) then hmax[htype] = d end
    ht = nil
  end
end)
T3 = on(0x91E5, function() scan = scan + 1 end)
T4 = on(0xE351, function() budget = budget + 1 end)
T5 = on(0x91E3, function() if not s_in then s_in = line() end end)
T6 = on(0x920D, function() if not s_idle then s_idle = line() end end)

-- drain
local dt, dl0, items, hdr, rem, ins = nil, nil, 0, 0, 0, 0
local dout = io.open("drain.txt", "w")
local sout = io.open("sched.txt", "w")
T7 = on(0xDEB7, function() dt = now(); dl0 = line(); items = 0; hdr = 0; rem = 0; ins = 0 end)
T8 = on(0xDEB9, function() items = items + 1 end)
T9 = on(0xDE83, function() hdr = hdr + 1 end)
T10 = on(0xE005, function() rem = rem + 1 end)
T11 = on(0xDE54, function() ins = ins + 1 end)
T12 = on(0xDFFD, function()
  if dt then
    dout:write(string.format("%d %d %d %d %d %d %d %d %d\n", fr, dl0, line(), math.floor(now() - dt), items, hdr, rem, ins,
      mem:read_u8(0x50)))
    dt = nil
  end
end)
TF = emu.register_frame_done(function()
  fr = fr + 1
  if fr >= TFROM and fr <= TTO then
    sout:write(string.format("%d %s %s %d %d %d\n", fr, s_in or "-", s_idle or "-", scan, disp, budget))
  end
  s_in = nil; s_idle = nil; scan = 0; disp = 0; budget = 0
end)
TS = emu.add_machine_stop_notifier(function()
  dout:close(); sout:close()
  local o = io.open("handler.txt", "w")
  for t = 0, 31 do
    if hn[t] then o:write(string.format("type %2d  n %6d  mean %7.1f  max %7.0f\n", t, hn[t], hsum[t] / hn[t], hmax[t])) end
  end
  o:close()
end)
