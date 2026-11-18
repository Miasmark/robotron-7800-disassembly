-- spans.lua: rb.lua plus elapsed time of routines, from an entry PC to any of its exit PCs.
--   SPANS  "name:start:end,end;name:start:end" (hex PCs). A span is counted only when an exit is
--          reached before the same start is entered again.
--   TFROM/TTO frames.  Output spans.txt: per span n, min, mean, max in CPU cycles of machine
--   time (DMA halts included), and the same for the samples that started and ended on raster
--   lines 236-262 or 0-15, where MARIA fetches almost nothing ("blank").
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
local function blank(l) return l >= 236 or l <= 15 end
local spans = {}
SP_TAPS = {}
for name, st, ends in string.gmatch(os.getenv("SPANS") or "", "(%w+):(%x+):([%x,]+)") do
  local s = {name = name, t = nil, l = nil, n = 0, sum = 0, min = 1e9, max = 0, bn = 0, bsum = 0, bmin = 1e9, bmax = 0}
  spans[#spans + 1] = s
  local a = tonumber(st, 16)
  SP_TAPS[#SP_TAPS + 1] = mem:install_read_tap(a, a, "sps" .. a, function(a2, d)
    if cpu.state["PC"].value == a and fr >= TFROM and fr <= TTO then s.t = now(); s.l = line() end
    return d
  end)
  for e in string.gmatch(ends, "%x+") do
    local b = tonumber(e, 16)
    SP_TAPS[#SP_TAPS + 1] = mem:install_read_tap(b, b, "spe" .. b .. name, function(a2, d)
      if cpu.state["PC"].value == b and s.t then
        local dt = now() - s.t
        s.n = s.n + 1; s.sum = s.sum + dt
        if dt < s.min then s.min = dt end
        if dt > s.max then s.max = dt end
        if blank(s.l) and blank(line()) then
          s.bn = s.bn + 1; s.bsum = s.bsum + dt
          if dt < s.bmin then s.bmin = dt end
          if dt > s.bmax then s.bmax = dt end
        end
        s.t = nil
      end
      return d
    end)
  end
end
SP_F = emu.register_frame_done(function() fr = fr + 1 end)
SP_S = emu.add_machine_stop_notifier(function()
  local o = io.open("spans.txt", "w")
  for _, s in ipairs(spans) do
    o:write(string.format("%-12s n %6d  min %5.0f mean %7.1f max %6.0f   blank: n %6d min %5.0f mean %7.1f max %6.0f\n",
      s.name, s.n, s.n > 0 and s.min or 0, s.n > 0 and s.sum / s.n or 0, s.max,
      s.bn, s.bn > 0 and s.bmin or 0, s.bn > 0 and s.bsum / s.bn or 0, s.bmax))
  end
  o:close()
end)
