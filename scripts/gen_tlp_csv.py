#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2026 Khadem Ullah
"""Convert a QEMU pci_cfg_* log into pcieshark-style CSV for TLP2HDL."""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

PCI_CFG_RE = re.compile(
    r"^(?:(?P<ts>\d+(?:\.\d+)?)\s*:\s*)?pci_cfg_(?P<op>read|write)\s+"
    r"(?P<dev>[A-Za-z0-9_.-]+)\s+"
    r"(?P<bdf>(?:[0-9A-Fa-f]{4}:)?[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}\.[0-9A-Fa-f])\s+"
    r"@(?P<offset>0x[0-9A-Fa-f]+)\s*(?P<arrow>->|<-)\s*(?P<value>0x[0-9A-Fa-f]+)\s*$"
)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("log", type=Path)
    ap.add_argument("-o", "--output", type=Path, default=Path("-"))
    ap.add_argument("-n", "--limit", type=int, default=0)
    args = ap.parse_args()

    lines = ["timestamp,direction,type,requester,completer,tag,length,addr,payload"]
    ns = 0
    for raw in args.log.read_text(encoding="utf-8", errors="replace").splitlines():
        m = PCI_CFG_RE.match(raw.strip())
        if not m:
            continue
        op = m.group("op")
        value = int(m.group("value"), 0)
        payload = " ".join(f"{(value >> (8 * i)) & 0xFF:02x}" for i in range(4))
        lines.append(
            f"{ns},{'TX' if op == 'write' else 'RX'},"
            f"{'CfgWr' if op == 'write' else 'CfgRd'},"
            f"{m.group('dev')},{m.group('bdf')},0,4,{m.group('offset')},{payload}"
        )
        ns += 120
        if args.limit and len(lines) - 1 >= args.limit:
            break

    text = "\n".join(lines) + "\n"
    if str(args.output) == "-":
        sys.stdout.write(text)
    else:
        args.output.write_text(text)
        print(f"wrote {len(lines) - 1} rows -> {args.output}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
