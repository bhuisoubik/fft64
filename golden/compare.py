#!/usr/bin/env python3
"""Golden-model comparison.

PASS/FAIL   : RTL output must equal the bit-accurate fixed-point model exactly
              (and, if a snapshot file is given, every per-stage memory image too).
INFORMATION : SQNR / max error of the RTL against numpy.fft (float64) computed on
              the *quantized* inputs, i.e. it measures arithmetic error only.
"""
import argparse, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
import fft_model as m

N = m.N


def read_input(path):
    frames, cur = [], []
    for line in open(path):
        a, b = line.split()
        cur.append((m.to_signed(int(a, 16), 16), m.to_signed(int(b, 16), 16)))
        if len(cur) == N:
            frames.append(cur); cur = []
    assert not cur, "input.hex is not a multiple of 64 samples"
    return frames


def read_output(path):
    vals = []
    for line in open(path):
        a, b = line.split()
        vals.append((m.to_signed(int(a, 16), 23), m.to_signed(int(b, 16), 23)))
    assert len(vals) % N == 0, f"output has {len(vals)} samples (not multiple of 64)"
    return [vals[i:i + N] for i in range(0, len(vals), N)]


def read_snaps(path):
    snaps = {}
    for line in open(path):
        f, l, a, re, im = map(int, line.split())
        snaps.setdefault((f, l), [None] * N)[a] = (re, im)
    return snaps


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="build")
    ap.add_argument("--in", dest="inp", default="input.hex")
    ap.add_argument("--out", default="output.hex")
    ap.add_argument("--snap", default=None)
    ap.add_argument("--plot", action="store_true")
    ap.add_argument("--max-report", type=int, default=5)
    a = ap.parse_args()
    p = lambda f: os.path.join(a.dir, f)

    xs = read_input(p(a.inp))
    outs = read_output(p(a.out))
    names = {}
    if os.path.exists(p("frames.txt")):
        for line in open(p("frames.txt")):
            i, n = line.split(); names[int(i)] = n
    snaps = read_snaps(p(a.snap)) if a.snap else None

    if len(outs) != len(xs):
        print(f"FAIL: {len(outs)} output frames for {len(xs)} input frames"); sys.exit(1)

    bad = 0
    sqnr, maxerr = [], []
    for f, (x, out) in enumerate(zip(xs, outs)):
        exp, ovf, esn = m.fft64(x, snapshots=True)
        assert not ovf, f"model overflow in frame {f}"
        mism = [(k, out[k], exp[k]) for k in range(N) if out[k] != exp[k]]
        if mism:
            bad += 1
            if bad <= a.max_report:
                print(f"MISMATCH frame {f} ({names.get(f, '?')}): {len(mism)} bins differ")
                if snaps:   # localize: first stage whose memory image differs
                    for lab in range(m.LOGN + 1):
                        got = snaps.get((f, lab))
                        if got is None:
                            print(f"  (no snapshot for stage label {lab})"); break
                        d = [ad for ad in range(N) if got[ad] != esn[lab][ad]]
                        if d:
                            print(f"  first divergence after {lab} completed stages, "
                                  f"{len(d)} addresses, first addr {d[0]}: RTL {got[d[0]]} model {esn[lab][d[0]]}")
                            break
                for k, g, e in mism[:3]:
                    print(f"  bin {k}: RTL {g} model {e}")
        elif snaps:
            for lab in range(m.LOGN + 1):
                got = snaps.get((f, lab))
                if got != esn[lab]:
                    bad += 1
                    print(f"MISMATCH frame {f}: stage snapshot {lab} differs although output matches")
                    break
        ref = np.fft.fft([complex(r, i) / 32768 for r, i in x])
        got = np.array([complex(r, i) / 32768 for r, i in out])
        err = got - ref
        e2 = np.sum(abs(err) ** 2)
        sqnr.append(10 * np.log10(np.sum(abs(ref) ** 2) / e2) if e2 > 0 else float("inf"))
        maxerr.append(np.max(np.maximum(abs(err.real), abs(err.imag))) * 32768)   # in LSBs (2^-15)

    n = len(xs)
    print(f"bit-exact vs fixed-point model: {n - bad}/{n} frames match"
          + (" (incl. all per-stage snapshots)" if snaps else ""))
    s = np.array(sqnr); me = np.array(maxerr)
    fin = s[np.isfinite(s)]
    print(f"SQNR vs numpy.fft (float64, quantized inputs): min {fin.min():.1f} dB, "
          f"median {np.median(fin):.1f} dB, max {fin.max():.1f} dB")
    w = int(np.argmin(np.where(np.isfinite(s), s, 1e9)))
    print(f"  worst frame: {w} ({names.get(w, '?')}) at {s[w]:.1f} dB")
    print(f"max component error: {me.max():.2f} LSB (1 LSB = 2^-15), median over frames {np.median(me):.2f} LSB")

    if a.plot:
        try:
            import matplotlib; matplotlib.use("Agg")
            import matplotlib.pyplot as plt
            fig, ax = plt.subplots(1, 2, figsize=(11, 3.8))
            ax[0].plot(s, ".", ms=4); ax[0].set_xlabel("frame"); ax[0].set_ylabel("SQNR (dB)")
            ax[0].set_title("RTL vs numpy.fft, per frame"); ax[0].grid(alpha=.3)
            ax[1].semilogy(np.maximum(me, 1e-3), ".", ms=4); ax[1].set_xlabel("frame")
            ax[1].set_ylabel("max component error (LSB)"); ax[1].grid(alpha=.3)
            fig.tight_layout(); fig.savefig(p("sqnr.png"), dpi=120)
            print(f"plot written to {p('sqnr.png')}")
        except ImportError:
            print("(matplotlib not available; plot skipped)")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
