-- dlwrites.lua: rb.lua plus a histogram, by raster line, of CPU writes to the playfield display
-- lists ($2280-$27FF) in frames TFROM..TTO -> dlwrites.txt ("line count"), and the writers
-- ("pc count"). Shows whether lists are ever written while they are being displayed (56-231).
dofile(os.getenv("RBLUA"))
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local scr
for _, s in pairs(M.screens) do scr = s break end
local TFROM = tonumber(os.getenv("TFROM") or "0")
local TTO = tonumber(os.getenv("TTO") or "99999999")
local fr = 0
local hist, pcs = {}, {}
local function line()
  local lines = scr.frame_period / scr.scan_period
  local left = scr:time_until_pos(0, 0) / scr.scan_period
  return math.floor((lines - left) % lines)
end
DW_TAP = mem:install_write_tap(0x2280, 0x27FF, "dlw", function(a, d)
  if fr >= TFROM and fr <= TTO then
    local l = line()
    hist[l] = (hist[l] or 0) + 1
    local pc = cpu.state["PC"].value
    pcs[pc] = (pcs[pc] or 0) + 1
  end
  return d
end)
DW_F = emu.register_frame_done(function() fr = fr + 1 end)
DW_S = emu.add_machine_stop_notifier(function()
  local o = io.open("dlwrites.txt", "w")
  for l = 0, 262 do if hist[l] then o:write(string.format("line %3d %d\n", l, hist[l])) end end
  local keys = {}
  for pc in pairs(pcs) do keys[#keys + 1] = pc end
  table.sort(keys)
  for _, pc in ipairs(keys) do o:write(string.format("pc %04X %d\n", pc, pcs[pc])) end
  o:close()
end)
