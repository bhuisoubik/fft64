#!/usr/bin/env python3
"""Generate all stimulus / expected-value files into an output directory.

  twiddle.hex     ROM image
  input.hex       system-test frames, one sample per line: "RRRR IIII" (Q1.15, hex)
  frames.txt      "<index> <name>" for every frame in input.hex
  cmul_vec.txt    b_re b_im w_re w_im | t_re t_im ovf          (hex)
  bfly_vec.txt    a b w | x y ovf                               (hex)
  agu_vec.txt     stage j a b tw                                (decimal)
"""
import argparse, math, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
import fft_model as m
from fft_model import hexw
import gen_twiddle

M = 32767


def clip16(v):
    return max(-32768, min(32767, int(round(v))))


def sgn(v):
    return 1 if v >= -1e-9 else -1


def directed_frames():
    n = np.arange(m.N)
    fr = []

    def add(name, samples):
        fr.append((name, [(clip16(r), clip16(i)) for r, i in samples]))

    z = [(0, 0)] * m.N
    s = list(z); s[0] = (M, M);                       add("impulse_n0_max", s)
    s = list(z); s[5] = (M, -32768);                  add("impulse_n5", s)
    s = list(z); s[63] = (-32768, 12345);             add("impulse_n63", s)
    add("dc_max_re", [(M, 0)] * m.N)
    add("dc_complex", [(M, M)] * m.N)
    add("tone_k5_complex", [(0.9 * M * math.cos(2 * math.pi * 5 * k / 64),
                             0.9 * M * math.sin(2 * math.pi * 5 * k / 64)) for k in n])
    add("tone_k5p5_offbin", [(0.9 * M * math.cos(2 * math.pi * 5.5 * k / 64),
                              0.9 * M * math.sin(2 * math.pi * 5.5 * k / 64)) for k in n])
    add("tone_k3_real_cos", [(0.95 * M * math.cos(2 * math.pi * 3 * k / 64), 0) for k in n])
    add("nyquist", [((M if k % 2 == 0 else -32768), 0) for k in n])
    add("alt_complex", [((M, -32768) if k % 2 == 0 else (-32768, M)) for k in n])
    # Worst-case growth: aligns signs of x[n] with the bin's phase so every term
    # adds to Re X[k]; |Re X[k]| ~ 64*M*4/pi ~ 81.5 (< 128, Q8.15 limit)
    for kk in (1, 3, 7):
        th = [2 * math.pi * kk * k / 64 for k in n]
        add(f"worst_growth_k{kk}", [(M * sgn(math.cos(t)), M * sgn(math.sin(t))) for t in th])
        add(f"worst_growth_k{kk}_neg", [(-32768 * sgn(math.cos(t)), -32768 * sgn(math.sin(t))) for t in th])
    add("all_max", [(M, M)] * m.N)
    add("all_min", [(-32768, -32768)] * m.N)
    return fr


def random_frames(seed):
    rng = np.random.RandomState(seed)
    fr = []
    n = np.arange(m.N)
    for i in range(60):
        fr.append((f"rand_fullscale_{i}", [tuple(map(int, v)) for v in rng.randint(-32768, 32768, size=(m.N, 2))]))
    for i in range(30):
        fr.append((f"rand_small_{i}", [tuple(map(int, v)) for v in rng.randint(-2048, 2048, size=(m.N, 2))]))
    for i in range(30):
        nt = rng.randint(1, 5)
        bins = rng.uniform(0, 64, nt)
        amps = rng.uniform(0.1, 0.9 / nt, nt)
        ph = rng.uniform(0, 2 * math.pi, nt)
        x = np.zeros(m.N, dtype=complex)
        for b, a, p in zip(bins, amps, ph):
            x += a * M * np.exp(1j * (2 * math.pi * b * n / 64 + p))
        fr.append((f"rand_tones_{i}", [(clip16(v.real), clip16(v.imag)) for v in x]))
    for i in range(20):
        s = [(0, 0)] * m.N
        s = list(s)
        for p in rng.choice(m.N, 3, replace=False):
            s[p] = tuple(map(int, rng.randint(-32768, 32768, 2)))
        fr.append((f"rand_sparse_{i}", s))
    for i in range(10):
        fr.append((f"rand_binary_{i}", [(int(rng.choice([M, -32768])), int(rng.choice([M, -32768]))) for _ in range(m.N)]))
    return fr


def write_system_vectors(out, seed):
    frames = directed_frames() + random_frames(seed)
    with open(os.path.join(out, "input.hex"), "w") as f, open(os.path.join(out, "frames.txt"), "w") as g:
        for idx, (name, smp) in enumerate(frames):
            g.write(f"{idx} {name}\n")
            for r, i in smp:
                f.write(f"{hexw(r, 16)} {hexw(i, 16)}\n")
    return len(frames)


def write_unit_vectors(out, seed):
    rng = np.random.RandomState(seed + 1)
    W = m.TWIDDLE
    # ---- cmul ----
    cm = []
    for wr, wi in W:                                    # all real twiddles x random b
        for _ in range(40):
            cm.append((int(rng.randint(-(1 << 21), 1 << 21)), int(rng.randint(-(1 << 21), 1 << 21)), wr, wi))
    for _ in range(600):                                # arbitrary 16-bit w, modest b
        cm.append((int(rng.randint(-(1 << 20), 1 << 20)), int(rng.randint(-(1 << 20), 1 << 20)),
                   int(rng.randint(-32768, 32768)), int(rng.randint(-32768, 32768))))
    for b in range(-9, 10):                             # exact rounding ties (w = +-0.5)
        for w in (8192, -8192, 4096, 2048):
            cm.append((b, 0, w, 0)); cm.append((0, b, 0, w)); cm.append((b, b, w, w))
    for b in (-(1 << 22), (1 << 22) - 1, 0, 1, -1):     # extremes (some overflow)
        for w in (32767, -32768, 16384, -16384, 0, 1, -1):
            cm.append((b, b, w, w)); cm.append((b, -b if b != -(1 << 22) else b, w, 0))
    with open(os.path.join(out, "cmul_vec.txt"), "w") as f:
        for b0, b1, w0, w1 in cm:
            t0, t1, ov = m.cmul(b0, b1, w0, w1)
            f.write(" ".join([hexw(b0, 23), hexw(b1, 23), hexw(w0, 16), hexw(w1, 16),
                              hexw(t0, 23), hexw(t1, 23), str(int(ov))]) + "\n")
    # ---- butterfly ----
    bf = []
    for k, (wr, wi) in enumerate(W):
        for _ in range(60):
            a = tuple(int(v) for v in rng.randint(-(1 << 20), 1 << 20, 2))
            b = tuple(int(v) for v in rng.randint(-(1 << 20), 1 << 20, 2))
            bf.append((a, b, (wr, wi)))
    for _ in range(100):                                # near-limit values (some overflow)
        a = tuple(int(v) for v in rng.randint(-(1 << 22), 1 << 22, 2))
        b = tuple(int(v) for v in rng.randint(-(1 << 22), 1 << 22, 2))
        bf.append((a, b, W[int(rng.randint(0, 32))]))
    with open(os.path.join(out, "bfly_vec.txt"), "w") as f:
        for a, b, w in bf:
            x, y, ov = m.butterfly(a, b, w)
            f.write(" ".join([hexw(a[0], 23), hexw(a[1], 23), hexw(b[0], 23), hexw(b[1], 23),
                              hexw(w[0], 16), hexw(w[1], 16),
                              hexw(x[0], 23), hexw(x[1], 23), hexw(y[0], 23), hexw(y[1], 23),
                              str(int(ov))]) + "\n")
    # ---- agu ----
    with open(os.path.join(out, "agu_vec.txt"), "w") as f:
        for s in range(m.LOGN):
            for j in range(m.N // 2):
                a, b, tw = m.agu(s, j)
                f.write(f"{s} {j} {a} {b} {tw}\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="build")
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    gen_twiddle.main(args.out)
    nf = write_system_vectors(args.out, args.seed)
    write_unit_vectors(args.out, args.seed)
    print(f"generated {nf} frames and unit vectors in {args.out}/ (seed={args.seed})")


if __name__ == "__main__":
    main()
