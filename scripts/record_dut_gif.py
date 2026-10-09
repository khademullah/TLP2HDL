#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2026 Khadem Ullah
"""Rebuild docs/assets/dut*-terminal-demo.{cast,gif} from a live DUT run.

Modes:
  single (default) → dut-terminal-demo  / make dut
  multi            → dut-multi-terminal-demo / make dut-multi

Requires: make compile first; agg on PATH (or --agg=...).
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SIM = ROOT / "obj_dir" / "Vtb_tlp_dpi"

MODES = {
    "single": {
        "cast": ROOT / "docs" / "assets" / "dut-terminal-demo.cast",
        "gif": ROOT / "docs" / "assets" / "dut-terminal-demo.gif",
        "cmd": "make dut",
        "make_line": "[MAKE] TRACE=traces/dut_ep_sample.csv MAX_TLPS=64 DUT_BDF=0300",
        "sim_args": [
            "+TRACE=traces/dut_ep_sample.csv",
            "+MAX_TLPS=64",
            "+DUT_BDF=0300",
        ],
        "height": 28,
        "target_sec": 15.0,
    },
    "multi": {
        "cast": ROOT / "docs" / "assets" / "dut-multi-terminal-demo.cast",
        "gif": ROOT / "docs" / "assets" / "dut-multi-terminal-demo.gif",
        "cmd": "make dut-multi",
        "make_line": "[MAKE] TRACE=traces/dut_multi_sample.csv MAX_TLPS=64 DUT_BDFS=0100,0200",
        "sim_args": [
            "+TRACE=traces/dut_multi_sample.csv",
            "+MAX_TLPS=64",
            "+DUT_BDFS=0100,0200",
        ],
        "height": 32,
        "target_sec": 18.0,
    },
}


def colorize(ln: str) -> str:
    if ln.startswith("[TLP]"):
        return f"\x1b[36m{ln}\x1b[0m\r\n"
    if ln.startswith("[DUT] RD") or ln.startswith("[DUT] WR") or ln.startswith("[DUT] SEED"):
        return f"\x1b[33m{ln}\x1b[0m\r\n"
    if ln.startswith("[DUT]"):
        return f"\x1b[1;33m{ln}\x1b[0m\r\n"
    if ln.startswith("[GATE]"):
        return f"\x1b[1;32m{ln}\x1b[0m\r\n"
    if ln.startswith(("[SUM]", "[C-DPI]", "[TB]", "[MAKE]", "./")):
        return f"\x1b[90m{ln}\x1b[0m\r\n"
    return ln + "\r\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--mode", choices=sorted(MODES), default="single")
    ap.add_argument("--agg", default="agg", help="path to asciinema/agg")
    ap.add_argument("--speed", type=float, default=1.2)
    ap.add_argument("--target-sec", type=float, default=None)
    args = ap.parse_args()
    cfg = MODES[args.mode]
    target = args.target_sec if args.target_sec is not None else cfg["target_sec"]
    cast_path: Path = cfg["cast"]
    gif_path: Path = cfg["gif"]

    if not SIM.is_file():
        print(f"missing {SIM}; run: make compile", file=sys.stderr)
        return 1

    proc = subprocess.run(
        [str(SIM), *cfg["sim_args"]],
        cwd=ROOT, capture_output=True, text=True, check=False,
    )
    outs = []
    for ln in (proc.stdout or "").splitlines():
        if not ln or ln.startswith("- ") or "Verilator" in ln or "Walltime" in ln:
            continue
        if "cpu " in ln or "S i m" in ln or ln.startswith("hdl/"):
            continue
        outs.append(ln)

    header = {
        "version": 2, "width": 100, "height": cfg["height"],
        "timestamp": int(time.time()),
        "env": {"SHELL": "/bin/bash", "TERM": "xterm-256color"},
    }
    events: list = []
    t = 0.15
    prompt = "\x1b[1;36mkhadem@tlp2hdl\x1b[0m:\x1b[1;34m~/TLP2HDL\x1b[0m$ "

    def emit(dt: float, s: str) -> None:
        nonlocal t
        t += dt
        events.append([round(t, 3), "o", s])

    emit(0.0, "\x1b[2J\x1b[H")
    emit(0.2, prompt)
    for ch in cfg["cmd"]:
        emit(0.04, ch)
    emit(0.2, "\r\n")
    emit(0.12, colorize(cfg["make_line"]))
    sim_disp = f'./obj_dir/Vtb_tlp_dpi {" ".join(cfg["sim_args"])}'
    emit(0.12, colorize(sim_disp))

    for ln in outs:
        if ln.startswith(("[TLP]", "[DUT] RD", "[DUT] WR", "[DUT] SEED")):
            dt = 0.28
        elif ln.startswith(("[DUT]", "[GATE]")):
            dt = 0.35
        elif ln.startswith("[SUM]"):
            dt = 0.25
        else:
            dt = 0.12
        emit(dt, colorize(ln))
    emit(0.4, prompt)

    if t > 0 and abs(t - target) > 0.5:
        scale = target / t
        for e in events:
            e[0] = round(e[0] * scale, 3)

    cast_path.parent.mkdir(parents=True, exist_ok=True)
    with cast_path.open("w", encoding="utf-8") as fh:
        fh.write(json.dumps(header) + "\n")
        for e in events:
            fh.write(json.dumps(e) + "\n")
    print(f"wrote {cast_path} (~{events[-1][0]:.1f}s, {len(events)} events)")

    cmd = [args.agg, "--font-size", "14", "--line-height", "1.25",
           "--theme", "monokai", "--speed", str(args.speed),
           str(cast_path), str(gif_path)]
    print(" ".join(cmd))
    r = subprocess.run(cmd)
    if r.returncode != 0:
        return r.returncode
    print(f"wrote {gif_path} ({gif_path.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
