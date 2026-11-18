"""hitstats.py RUNDIR FROM TO NAME,NAME,...   summary of hits.txt columns (min/mean/max, frames
nonzero, frames zero) between two frames; names label the columns in HITS order."""
import os
import sys

rd, lo, hi = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
names = sys.argv[4].split(",")
cols = [[] for _ in names]
for line in open(os.path.join(rd, "hits.txt")):
    p = line.split()
    f = int(p[0])
    if lo <= f <= hi:
        for i in range(len(names)):
            cols[i].append((int(p[1 + i].split("@")[0]), f))
print("frames %d..%d (%d)" % (lo, hi, len(cols[0])))
for n, c in zip(names, cols):
    v = [x[0] for x in c]
    mx = max(c)
    mn = min(c)
    print("%-10s min %5d (f%d)  mean %8.2f  max %5d (f%d)  nonzero %5d  zero %5d  total %d" % (
        n, mn[0], mn[1], sum(v) / len(v), mx[0], mx[1], sum(1 for x in v if x), sum(1 for x in v if not x), sum(v)))
