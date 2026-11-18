"""drainstats.py RUNDIR [FROM TO]: summary of timing.lua's drain.txt and sched.txt."""
import os
import sys

rd = sys.argv[1]
lo = int(sys.argv[2]) if len(sys.argv) > 2 else 0
hi = int(sys.argv[3]) if len(sys.argv) > 3 else 10 ** 9
rows = [list(map(int, l.split())) for l in open(os.path.join(rd, "drain.txt"))]
rows = [r for r in rows if lo <= r[0] <= hi]
n = len(rows)
cyc = sum(r[3] for r in rows)
items = sum(r[4] for r in rows)
hdr = sum(r[5] for r in rows)
rem = sum(r[6] for r in rows)
ins = sum(r[7] for r in rows)
print("drains %d  mean cycles %.0f  max cycles %d  items/drain mean %.2f max %d" % (
    n, cyc / n, max(r[3] for r in rows), items / n, max(r[4] for r in rows)))
print("per item %.0f cycles; header writes %d (%.2f/item), removals %d, inserts %d" % (
    cyc / max(items, 1), hdr, hdr / max(items, 1), rem, ins))
left = [r for r in rows if r[8] != 0]
print("drains that ended with work pending ($50 != 0): %d" % len(left))
# end line distribution: lines past 262 wrap to the next frame
ends = []
for r in rows:
    e = r[2] if r[2] >= r[1] else r[2] + 263
    ends.append(e)
print("drain start line min %d max %d; end line (263+ = next frame) mean %.1f max %d; ends at/after line 56 next frame: %d" % (
    min(r[1] for r in rows), max(r[1] for r in rows), sum(ends) / n, max(ends), sum(1 for e in ends if e >= 263 + 56)))
worst = sorted(rows, key=lambda r: -r[3])[:5]
for r in worst:
    print("   frame %d lines %d-%d cycles %d items %d hdr %d rem %d ins %d pending %d" % tuple(r))
srows = [l.split() for l in open(os.path.join(rd, "sched.txt"))]
srows = [r for r in srows if lo <= int(r[0]) <= hi]
disp = [int(r[4]) for r in srows]
print("frames %d  dispatches mean %.2f max %d  budget-hit frames %d  frames with no idle spin %d" % (
    len(srows), sum(disp) / len(disp), max(disp), sum(1 for r in srows if int(r[5])), sum(1 for r in srows if r[2] == "-")))
idle = [int(r[2]) for r in srows if r[2] != "-"]
print("first idle spin line: mean %.0f min %d max %d (the playfield is lines 56-231)" % (sum(idle) / len(idle), min(idle), max(idle)))
