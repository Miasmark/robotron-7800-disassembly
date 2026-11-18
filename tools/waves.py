"""waves.py: print the wave records ($EF0A + 16*wave, 41 records) and the per-difficulty and
per-speed-index tables. Field names per docs/FINDINGS.md."""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
rom = open(os.path.join(HERE, "..", "work", "robotron.a78"), "rb").read()[128:]


def b(a, n=1):
    return rom[a - 0x8000:a - 0x8000 + n]


names = ["grunt", "mom", "dad", "mikey", "hulk", "spher", "quark", "enfMax", "tank", "brain",
         "f10", "f11", "f12", "f13", "elType", "elec"]
print("wave " + " ".join("%6s" % n for n in names) + "  objects")
for w in range(0, 41):
    r = b(0xEF0A + 16 * w, 16)
    tot = sum(r[i] for i in (0, 1, 2, 3, 4, 5, 6, 8, 9, 15))
    print("%4d " % w + " ".join("%6d" % x for x in r) + "  %d" % tot)
print()
for name, a, n in (("ED62 $72->$EC enforcer-spawn chance base", 0xED62, 5), ("ED67 $71 enforcer fire reload", 0xED67, 5),
                   ("ED6C $6F start speed index", 0xED6C, 5), ("ED71 $75 lives", 0xED71, 5)):
    print("%-45s %s" % (name, " ".join("%02X" % x for x in b(a, n))))
for name, a in (("ED76 grunt timer base ($CC)", 0xED76), ("EDBC hulk timer ($CE)", 0xEDBC),
                ("EE02 hulk $1C2B seed", 0xEE02), ("EE48 spheroid spawn delay ($EB)", 0xEE48),
                ("EE8E spheroid/enforcer timer ($CF)", 0xEE8E), ("EED4 brain timer ($D2)", 0xEED4)):
    print(name)
    r = b(a, 70)
    for i in range(0, 70, 10):
        print("   %2d: %s" % (i, " ".join("%02X" % x for x in r[i:i + 10])))
