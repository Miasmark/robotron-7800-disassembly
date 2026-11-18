"""hx.py ADDR [LEN] [--w]   hex dump of the ROM at a CPU address (--w: as little-endian words)
   hx.py --ram DUMP ADDR [LEN]   the same from a RAM dump that starts at 0"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[1:]
words = "--w" in args
if words:
    args.remove("--w")
if args[0] == "--ram":
    data = open(args[1], "rb").read()
    base = 0
    args = args[2:]
else:
    data = open(os.path.join(HERE, "..", "work", "robotron.a78"), "rb").read()[128:]
    base = 0x8000
a = int(args[0], 16)
n = int(args[1], 0) if len(args) > 1 else 64
b = data[a - base:a - base + n]
if words:
    for i in range(0, len(b) - 1, 16):
        print("%04X: %s" % (a + i, " ".join("%04X" % (b[j] | b[j + 1] << 8) for j in range(i, min(i + 16, len(b) - 1), 2))))
else:
    for i in range(0, len(b), 16):
        print("%04X: %s" % (a + i, " ".join("%02X" % x for x in b[i:i + 16])))
