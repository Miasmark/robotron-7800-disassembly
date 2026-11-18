"""ann.py: merge work-in-progress notes into annotations.json, then re-disassemble.

  python -I tools/ann.py                 apply tools/notes.py (ENTRIES, LABELS, RAM, COMMENTS,
                                         HEADERS, BLOCKS) to annotations.json, run disasm.py,
                                         write work/src/rom.asm and the compact work/c.txt
  python -I tools/ann.py --exec FILE     also add, as entries, executed addresses from a
                                         run's exec.txt that the current listing has as data

notes.py is plain Python data so that names can be changed in one place; annotations.json is
what the toolkit reads and stays the record.
"""
import importlib.util
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)
TK = os.path.join(PROJ, "..", "..", "a7800-toolkit", "tools")
ANN = os.path.join(PROJ, "annotations.json")
ROM = os.path.join(PROJ, "work", "robotron.a78")


def code_addrs():
    s = set()
    p = os.path.join(PROJ, "work", "src", "rom.asm")
    if not os.path.exists(p):
        return s
    for line in open(p, encoding="utf-8", errors="replace"):
        if ".byte" in line or ".word" in line:
            continue
        m = re.search(r"; ([0-9A-F]{4}): ", line)
        if m:
            s.add(int(m.group(1), 16))
    return s


def main():
    spec = importlib.util.spec_from_file_location("notes", os.path.join(HERE, "notes.py"))
    notes = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(notes)
    ann = json.load(open(ANN))
    entries = list(ann.get("entries", []))
    for e in notes.ENTRIES:
        k = "rom:%04X" % e
        if k not in entries:
            entries.append(k)
    if "--exec" in sys.argv:
        f = sys.argv[sys.argv.index("--exec") + 1]
        have = code_addrs()
        dyn = ann.setdefault("_dynamic", {}).setdefault("executed_entries", [])
        added = 0
        for line in open(f):
            a = int(line.split()[0], 16)
            if a not in have:
                k = "rom:%04X" % a
                if k not in entries:
                    entries.append(k)
                    dyn.append(k)
                    added += 1
        print("added %d executed addresses as entries" % added)
    ann["entries"] = entries
    lab = ann.setdefault("labels", {})
    for a, n in notes.LABELS.items():
        lab["rom:%04X" % a] = n
    ram = ann.setdefault("ram", {})
    for a, n in notes.RAM.items():
        ram["%X" % a if a > 0xFF else "%02X" % a] = n
    com = ann.setdefault("comments", {})
    for a, n in notes.COMMENTS.items():
        com["rom:%04X" % a] = n
    hd = ann.setdefault("headers", {})
    for a, n in notes.HEADERS.items():
        hd["rom:%04X" % a] = n
    ann["blocks"] = [dict(loc="rom:%04X" % b[0], end="rom:%04X" % (b[1] + 1), note=b[2], **(b[3] if len(b) > 3 else {}))
                     for b in notes.BLOCKS]
    if getattr(notes, "RAM_VECTORS", None):
        ann["ram_vectors"] = notes.RAM_VECTORS
    if getattr(notes, "ROM_NOTE", None):
        ann.setdefault("notes", {})["rom"] = notes.ROM_NOTE
    json.dump(ann, open(ANN, "w"), indent=2)
    r = subprocess.run([sys.executable, "-I", os.path.join(TK, "disasm.py"), ROM, "-c", ANN, "-o",
                        os.path.join(PROJ, "work", "src"), "--cycles"], capture_output=True, text=True)
    out = r.stdout + r.stderr
    for line in out.splitlines():
        if "%" in line or "rror" in line or "arning" in line:
            print(line)
    subprocess.run([sys.executable, "-I", os.path.join(HERE, "compact.py"),
                    os.path.join(PROJ, "work", "src", "rom.asm"), os.path.join(PROJ, "work", "c.txt")])


if __name__ == "__main__":
    main()
