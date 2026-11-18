"""bill.py DUMP [DUMP ...]: for rb.lua RAM dumps (ram_fNNNNN.bin, $0000-$27FF):
  - live objects by type (type array $1E8C, state $1F91), slots in use
  - per playfield zone: header count ($2131), enemy count ($1963), list bytes
  - MARIA's DMA cost, by the toolkit's zonebill.py (a copy of $1800-$27FF with the registers
    the game always uses: DPPH/DPPL $1804, CTRL $40)."""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TK = os.path.join(HERE, "..", "..", "..", "a7800-toolkit", "tools")
NAMES = {0: "free/player", 1: "grunt", 2: "mommy", 3: "daddy", 4: "mikey", 5: "hulk", 6: "spheroid",
         7: "quark", 8: "enforcer", 9: "tank", 10: "brain", 11: "prog", 12: "spark", 13: "cruise",
         14: "shell", 15: "shot/effect", 16: "electrode"}

for path in sys.argv[1:]:
    ram = open(path, "rb").read()
    print("==", os.path.basename(path))
    types = {}
    live = 0
    for s in range(0x57):
        t = ram[0x1E8C + s] & 0x1F
        st = ram[0x1F91 + s]
        if st & 3 or (s and t):
            live += 1
            types[t] = types.get(t, 0) + 1
    print("  slots with an object: %d of 87   " % live + ", ".join("%s %d" % (NAMES.get(t, t), n) for t, n in sorted(types.items())))
    tot_h = 0
    for z in range(1, 12):
        h = ram[0x2131 + z]
        tot_h += h
        print("  zone %2d (y %3d-%3d, list $%04X): headers %2d  enemies counted %2d  list bytes %3d" % (
            z, z * 16, z * 16 + 15, 0x2200 + z * 0x80, h, ram[0x1963 + z], h * 4 + 2))
    print("  headers in the 11 playfield lists: %d (%d bytes of 1,408)" % (tot_h, tot_h * 4))
    out = os.path.splitext(path)[0] + "-survey-ram-00000"
    open(out + ".bin", "wb").write(ram[0x1800:0x2800])
    open(out + ".txt", "w").write("dpph=18 dppl=04 ctrl=40\n")
    r = subprocess.run([sys.executable, "-I", os.path.join(TK, "zonebill.py"), "--zones", out + ".bin"],
                       capture_output=True, text=True)
    print(r.stdout + r.stderr)
