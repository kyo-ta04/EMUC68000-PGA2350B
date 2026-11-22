#!/usr/bin/env python3
"""Compatibility shim (M6 factoring).

The hardware variant is built by build.py from the parts in
parts/; the string-rewrite approach this file used through M5g
has been retired.  run_hw.py invokes this file by name, so it
stays as a thin delegate: it runs the HW build of build.py and
propagates its exit status.
"""
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

if __name__ == "__main__":
    r = subprocess.run([sys.executable, str(HERE / "build.py"), "hw"])
    sys.exit(r.returncode)
