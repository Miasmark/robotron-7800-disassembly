"""run.py NAME [KEY=VALUE ...] [--lua other.lua] [--bios]

One windowless MAME run of Robotron in work/runs/NAME (its own cfg, nvram and snapshot
folders, ui.ini with skip_warnings 1). KEY=VALUE pairs become the environment of tools/rb.lua
(see its header). Prints the files the run wrote.
"""
import glob
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)
MAME = os.environ.get("A7800_MAME", "a78.exe")
ROM = os.path.join(PROJ, "work", "robotron.a78")


def main():
    args = sys.argv[1:]
    name = args.pop(0)
    lua = os.path.join(HERE, "rb.lua")
    bios = False
    env = dict(os.environ)
    while args:
        a = args.pop(0)
        if a == "--lua":
            lua = os.path.abspath(args.pop(0))
        elif a == "--bios":
            bios = True
        else:
            k, v = a.split("=", 1)
            env[k] = v
    rd = os.path.join(PROJ, "work", "runs", name)
    shutil.rmtree(rd, ignore_errors=True)
    os.makedirs(os.path.join(rd, "cfg"))
    with open(os.path.join(rd, "ui.ini"), "w") as o:
        o.write("skip_warnings 1\n")
    shutil.copy(ROM, os.path.join(rd, "cart.a78"))
    cmd = [MAME, "a7800", "-cart", "cart.a78", "-skip_gameinfo", "-video", "none",
           "-sound", "none", "-nothrottle", "-inipath", ".", "-cfg_directory", "cfg",
           "-nvram_directory", "nv", "-snapshot_directory", "snap",
           "-rompath", os.environ.get("A7800_BIOS", "roms"),
           "-autoboot_script", lua]
    if not bios:
        cmd[3:3] = []
        cmd += ["-bios", "skip"]
    with open(os.path.join(rd, "mame.out"), "w") as o:
        subprocess.run(cmd, cwd=rd, env=env, stdout=o, stderr=subprocess.STDOUT, timeout=3000)
    out = open(os.path.join(rd, "mame.out")).read().strip()
    if out:
        print(out[:2000])
    for p in sorted(glob.glob(os.path.join(rd, "**", "*"), recursive=True)):
        if os.path.isfile(p) and not p.endswith("cart.a78"):
            print("  %-40s %d" % (os.path.relpath(p, rd), os.path.getsize(p)))


if __name__ == "__main__":
    main()
