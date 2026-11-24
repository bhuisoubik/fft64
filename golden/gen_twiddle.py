#!/usr/bin/env python3
"""Write twiddle.hex: 32 lines of {re[15:0], im[15:0]} (Q2.14), the single source
for the RTL ROM."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from fft_model import TWIDDLE, hexw


def main(outdir):
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "twiddle.hex"), "w") as f:
        for wr, wi in TWIDDLE:
            f.write(hexw(wr, 16) + hexw(wi, 16) + "\n")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "build")
