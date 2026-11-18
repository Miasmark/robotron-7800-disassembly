-- rb.lua: one windowless scripted run of Robotron 2084 (7800) on the user's MAME fork.
-- Everything is set by environment variables; files are written into the cwd (the run folder).
--   SCRIPT  "frames:p1:p2:buttons;..."  p1/p2 are letter sets of l r u d (or -);
--           buttons: +1 P1 fire, +2 P2 fire, +8 Select, +16 Reset, +4 Pause.
--           RAND=seed  instead of following p1/p2 after the script's end, pick random sticks
--           every RANDN frames (default 20) until END.
--   END     frame to exit on
--   SNAPS   "a,b,c" frames to snapshot;  SNAPEVERY=n from SNAPFROM
--   DUMPS   "a,b,c" frames at which RAM $0000-$27FF is written to ram_fNNNNN.bin
--           (TIA/MARIA/RIOT register ranges are written as zero, not read)
--   PEEK    "addr,addr" hex; frames.txt gets one line per frame with the bytes (hex)
--   POKES   "frame:addr=val,addr=val;..." hex addr/val, written at the end of that frame
--   HOLD    "addr=val,addr=val" hex, written at the end of every frame from HOLDFROM (default 1)
--   EXEC    1: log every executed ROM address ($8000-$FFFF) to exec.txt (hex per line, with count)
--   PCW     "lo-hi" hex range: every write tagged with PC, frames PCWFROM..PCWTO -> pcw.txt
--           as aggregated "addr pc count firstframe lastframe"
--   PCR     "lo-hi" hex range of reads tagged by PC (aggregated) -> pcr.txt
--   REGW    1: log writes to MARIA regs $20-$3F with frame/line/pc -> regw.txt (first REGWN frames
--           from REGWFROM)
--   HITS    "addr,addr" hex PCs: per frame count of executions -> hits.txt ("frame c1 c2 ..")
--           with HITLINE=1 also the raster line of every hit; HITLINE=2 first-last line only
--   NMI     1: count NMIs per frame and log line of each in nmi.txt (frames NMIFROM..NMITO)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["program"]
local P = M.ioport.ports
local scr
for _, s in pairs(M.screens) do scr = s break end

local function fld(n)
  for _, t in ipairs({":JOYSTICKS", ":BUTTONS", ":joysticks", ":buttons"}) do
    local f = P[t] and P[t].fields[n]
    if f then return f end
  end
end
local s1 = {l = fld("P1 Left"), r = fld("P1 Right"), u = fld("P1 Up"), d = fld("P1 Down")}
local s2 = {l = fld("P2 Left"), r = fld("P2 Right"), u = fld("P2 Up"), d = fld("P2 Down")}
local b1, b2 = fld("P1 Button 1"), fld("P2 Button 1")
local pause, select, reset
for _, t in ipairs({":CONSOLE", ":console", ":console_buttons"}) do
  if P[t] then
    for name, f in pairs(P[t].fields) do
      if name:find("Pause") then pause = f end
      if name:find("Select") then select = f end
      if name:find("Reset") then reset = f end
    end
  end
end

local function hexlist(s)
  local t = {}
  for a in string.gmatch(s or "", "%x+") do t[#t + 1] = tonumber(a, 16) end
  return t
end
local function numset(s)
  local t = {}
  for a in string.gmatch(s or "", "%d+") do t[tonumber(a)] = true end
  return t
end

local steps = {}
for n, a, b, c in string.gmatch(os.getenv("SCRIPT") or "", "(%d+):([lrud%-]+):([lrud%-]+):(%d+)") do
  steps[#steps + 1] = {tonumber(n), a, b, tonumber(c)}
end
local total = 0
for _, s in ipairs(steps) do total = total + s[1] end
local END = tonumber(os.getenv("END") or tostring(total))
local snaps = numset(os.getenv("SNAPS"))
local SNAPEVERY = tonumber(os.getenv("SNAPEVERY") or "0")
local SNAPFROM = tonumber(os.getenv("SNAPFROM") or "0")
local dumps = numset(os.getenv("DUMPS"))
local peek = hexlist(os.getenv("PEEK"))
local pokes = {}
for fr, list in string.gmatch(os.getenv("POKES") or "", "(%d+):([^;]+)") do
  local t = pokes[tonumber(fr)] or {}
  for ad, val in string.gmatch(list, "(%x+)=(%x+)") do t[#t + 1] = {tonumber(ad, 16), tonumber(val, 16)} end
  pokes[tonumber(fr)] = t
end
local hold = {}
for ad, val in string.gmatch(os.getenv("HOLD") or "", "(%x+)=(%x+)") do
  hold[#hold + 1] = {tonumber(ad, 16), tonumber(val, 16)}
end
local HOLDFROM = tonumber(os.getenv("HOLDFROM") or "1")
local RAND = os.getenv("RAND") and tonumber(os.getenv("RAND"))
local RANDN = tonumber(os.getenv("RANDN") or "20")
local rs = RAND or 1
local function rnd(n)
  rs = (rs * 1103515245 + 12345) % 2147483648
  return math.floor(rs / 65536) % n
end
local dirs = {"-", "l", "r", "u", "d", "lu", "ld", "ru", "rd"}

local f = 0
local function line()
  local lines = scr.frame_period / scr.scan_period
  local left = scr:time_until_pos(0, 0) / scr.scan_period
  return math.floor((lines - left) % lines)
end

-- executed addresses
local exec = nil
if os.getenv("EXEC") then
  exec = {}
  RB_EXEC = mem:install_read_tap(0x8000, 0xFFFF, "rbexec", function(a, d)
    if cpu.state["PC"].value == a then exec[a] = (exec[a] or 0) + 1 end
    return d
  end)
end

-- PC-tagged writes
local pcw, pcwlo, pcwhi
local PCWFROM = tonumber(os.getenv("PCWFROM") or "0")
local PCWTO = tonumber(os.getenv("PCWTO") or "99999999")
if os.getenv("PCW") then
  pcw = {}
  local a, b = string.match(os.getenv("PCW"), "(%x+)-(%x+)")
  pcwlo, pcwhi = tonumber(a, 16), tonumber(b, 16)
  RB_PCW = mem:install_write_tap(pcwlo, pcwhi, "rbpcw", function(a2, d)
    if f >= PCWFROM and f <= PCWTO then
      local k = a2 * 65536 + cpu.state["PC"].value
      local e = pcw[k]
      if e then e[1] = e[1] + 1; e[3] = f else pcw[k] = {1, f, f} end
    end
    return d
  end)
end
local pcr
if os.getenv("PCR") then
  pcr = {}
  local a, b = string.match(os.getenv("PCR"), "(%x+)-(%x+)")
  RB_PCR = mem:install_read_tap(tonumber(a, 16), tonumber(b, 16), "rbpcr", function(a2, d)
    if f >= PCWFROM and f <= PCWTO then
      local k = a2 * 65536 + cpu.state["PC"].value
      local e = pcr[k]
      if e then e[1] = e[1] + 1; e[3] = f else pcr[k] = {1, f, f} end
    end
    return d
  end)
end

-- MARIA register writes
local regw
local REGWFROM = tonumber(os.getenv("REGWFROM") or "0")
local REGWN = tonumber(os.getenv("REGWN") or "4")
if os.getenv("REGW") then
  regw = io.open("regw.txt", "w")
  RB_REGW = mem:install_write_tap(0x20, 0x3F, "rbregw", function(a, d)
    if f >= REGWFROM and f < REGWFROM + REGWN then
      regw:write(string.format("%d %d %04X %02X=%02X\n", f, line(), cpu.state["PC"].value, a, d & 0xFF))
    end
    return d
  end)
end

-- per-frame hit counts of PCs
local hits = hexlist(os.getenv("HITS"))
local hitc, hitl, hitf = {}, {}, {}
local hout
local HITLINE = os.getenv("HITLINE")
if #hits > 0 then
  hout = io.open("hits.txt", "w")
  RB_HITS = {}
  for i, a in ipairs(hits) do
    hitc[i] = 0
    RB_HITS[i] = mem:install_read_tap(a, a, "rbhit" .. i, function(a2, d)
      if cpu.state["PC"].value == a then
        hitc[i] = hitc[i] + 1
        if HITLINE == "1" then hitl[i] = (hitl[i] and (hitl[i] .. ",") or "") .. line()
        elseif HITLINE then
          local l = line()
          if not hitf[i] then hitf[i] = l end
          hitl[i] = hitf[i] .. "-" .. l
        end
      end
      return d
    end)
  end
end

local fout = (#peek > 0) and io.open("frames.txt", "w")

local function dump(fr)
  local o = io.open(string.format("ram_f%05d.bin", fr), "wb")
  local t = {}
  for a = 0, 0x27FF do
    local v = 0
    if (a >= 0x40 and a < 0x100) or (a >= 0x140 and a < 0x200) or a >= 0x1800 then v = mem:read_u8(a) end
    t[#t + 1] = string.char(v)
  end
  o:write(table.concat(t))
  o:close()
end

local curp1, curp2 = "-", "-"
RB_FRAME = emu.register_frame_done(function()
  f = f + 1
  local t, cur = f, nil
  for _, s in ipairs(steps) do
    if t <= s[1] then cur = s break end
    t = t - s[1]
  end
  local p1, p2, b = "-", "-", 0
  if cur then p1, p2, b = cur[2], cur[3], cur[4]
  elseif RAND then
    if (f % RANDN) == 0 then curp1 = dirs[rnd(#dirs) + 1]; curp2 = dirs[rnd(#dirs - 1) + 2] end
    p1, p2 = curp1, curp2
    b = 1
  end
  for k, fl in pairs(s1) do fl:set_value(p1:find(k) and 1 or 0) end
  for k, fl in pairs(s2) do fl:set_value(p2:find(k) and 1 or 0) end
  b1:set_value((b % 2 == 1) and 1 or 0)
  b2:set_value((math.floor(b / 2) % 2 == 1) and 1 or 0)
  if pause then pause:set_value((b % 8 >= 4) and 1 or 0) end
  if select then select:set_value((b % 16 >= 8) and 1 or 0) end
  if reset then reset:set_value((b >= 16) and 1 or 0) end
  if snaps[f] or (SNAPEVERY > 0 and f >= SNAPFROM and (f % SNAPEVERY) == 0) then M.video:snapshot() end
  if dumps[f] then dump(f) end
  if fout then
    local v = {}
    for _, a in ipairs(peek) do v[#v + 1] = string.format("%02X", mem:read_u8(a)) end
    fout:write(f .. " " .. table.concat(v, " ") .. "\n")
  end
  if hout then
    local v = {}
    for i = 1, #hits do
      v[#v + 1] = tostring(hitc[i]) .. (HITLINE and ("@" .. (hitl[i] or "-")) or "")
      hitc[i] = 0; hitl[i] = nil; hitf[i] = nil
    end
    hout:write(f .. " " .. table.concat(v, " ") .. "\n")
  end
  local p = pokes[f]
  if p then for _, w in ipairs(p) do mem:write_u8(w[1], w[2]) end end
  if f >= HOLDFROM then for _, w in ipairs(hold) do mem:write_u8(w[1], w[2]) end end
  if f >= END then M:exit() end
end)

RB_STOP = emu.add_machine_stop_notifier(function()
  if fout then fout:close() end
  if hout then hout:close() end
  if regw then regw:close() end
  if exec then
    local o = io.open("exec.txt", "w")
    local keys = {}
    for a in pairs(exec) do keys[#keys + 1] = a end
    table.sort(keys)
    for _, a in ipairs(keys) do o:write(string.format("%04X %d\n", a, exec[a])) end
    o:close()
  end
  local function agg(tbl, name)
    local o = io.open(name, "w")
    local keys = {}
    for k in pairs(tbl) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local e = tbl[k]
      o:write(string.format("%04X %04X %d %d %d\n", math.floor(k / 65536), k % 65536, e[1], e[2], e[3]))
    end
    o:close()
  end
  if pcw then agg(pcw, "pcw.txt") end
  if pcr then agg(pcr, "pcr.txt") end
end)
