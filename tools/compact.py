"""compact.py LISTING OUT: a narrow copy of a toolkit listing for reading
("ADDR  MNEMONIC OPERAND  ; comment"), labels and xref lines kept short."""
import re
import sys

src, out = sys.argv[1], sys.argv[2]
o = open(out, "w")
for line in open(src, encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    m = re.match(r"^\s+(\S+)\s*(.*?)\s*; ([0-9A-F]{4}): (?:[0-9A-F]{2} ?)+\s*(\d\+?)?\s*(.*)$", line)
    if m and not line.lstrip().startswith(".byte"):
        op, arg, addr, cyc, rest = m.groups()
        arg = arg.replace("ram_00", "$").replace("ram_", "$")
        o.write("%s %s %s%s\n" % (addr, op, arg, ("  ; " + rest) if rest else ""))
        continue
    if line.startswith("; xrefs:"):
        x = line[8:].replace("rom:", "").strip()
        if len(x) > 70:
            x = x[:70] + "..."
        o.write(";x " + x + "\n")
        continue
    m = re.match(r"^\s+\.byte\s+(.*?)\s*; ([0-9A-F]{4})", line)
    if m:
        o.write("%s .byte %s\n" % (m.group(2), m.group(1).replace("$", "").replace(",", " ")))
        continue
    o.write(line + "\n")
o.close()
