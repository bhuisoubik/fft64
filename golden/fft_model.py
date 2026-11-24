"""Bit-accurate fixed-point model of the 64-pt radix-2 DIT FFT accelerator.

Everything is plain Python ints, mirroring the RTL exactly:
  input  Q1.15 (16 b)   twiddle Q2.14 (16 b)   memory/output Q8.15 (23 b)
  complex multiply: 4 products, add/sub exact, round half-up ONCE (+2^13, >>14)
  butterfly add/sub exact (no rounding, no saturation)
  bit-reversal on load, natural-order output
"""
import math

N, LOGN = 64, 6
DW, TW_FRAC = 23, 14
DMIN, DMAX = -(1 << (DW - 1)), (1 << (DW - 1)) - 1


def bitrev6(x):
    return int(f"{x:06b}"[::-1], 2)


def twiddle_table():
    """W64^k = cos(2*pi*k/64) - j*sin(2*pi*k/64) in Q2.14, k=0..31, round-half-up."""
    tab = []
    for k in range(N // 2):
        a = 2 * math.pi * k / N
        wr = math.floor(math.cos(a) * (1 << TW_FRAC) + 0.5)
        wi = math.floor(-math.sin(a) * (1 << TW_FRAC) + 0.5)
        assert -(1 << 15) <= wr < (1 << 15) and -(1 << 15) <= wi < (1 << 15)
        tab.append((wr, wi))
    return tab


TWIDDLE = twiddle_table()


def agu(s, j):
    """(A address, B address, twiddle index) for stage s, butterfly j."""
    lo = j & ((1 << s) - 1)
    a = ((j >> s) << (s + 1)) | lo
    b = a | (1 << s)
    tw = lo << (LOGN - 1 - s)
    return a, b, tw


def _rnd(v):
    return (v + (1 << (TW_FRAC - 1))) >> TW_FRAC


def fits(v):
    return DMIN <= v <= DMAX


def cmul(bre, bim, wre, wim):
    """Returns (t_re, t_im, ovf). Values are the *unwrapped* rounded results."""
    tre = _rnd(bre * wre - bim * wim)
    tim = _rnd(bre * wim + bim * wre)
    return tre, tim, not (fits(tre) and fits(tim))


def butterfly(a, b, w):
    """a, b = (re, im) Q8.15; w = (re, im) Q2.14. Returns (x, y, ovf)."""
    tre, tim, ov = cmul(b[0], b[1], w[0], w[1])
    x = (a[0] + tre, a[1] + tim)
    y = (a[0] - tre, a[1] - tim)
    ov = ov or not all(fits(v) for v in (*x, *y))
    return x, y, ov


def fft64(x, snapshots=False):
    """x: list of 64 (re, im) Q1.15 ints.

    Returns (out, ovf[, snaps]).  snaps[0] = memory after load (bit-reversed),
    snaps[s+1] = memory after stage s  (each a list of 64 (re, im) by address).
    """
    assert len(x) == N
    mem = [None] * N
    for i, v in enumerate(x):
        mem[bitrev6(i)] = (int(v[0]), int(v[1]))
    snaps = [list(mem)]
    ovf = False
    for s in range(LOGN):
        for j in range(N // 2):
            a, b, tw = agu(s, j)
            xo, yo, ov = butterfly(mem[a], mem[b], TWIDDLE[tw])
            ovf = ovf or ov
            mem[a], mem[b] = xo, yo
        snaps.append(list(mem))
    return (mem, ovf, snaps) if snapshots else (mem, ovf)


def to_signed(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


def hexw(v, bits):
    return format(v & ((1 << bits) - 1), f"0{(bits + 3) // 4}x")


if __name__ == "__main__":
    # Self-checks: AGU covers every address once per stage; model ~ float DFT.
    import numpy as np
    for s in range(LOGN):
        seen = set()
        for j in range(N // 2):
            a, b, tw = agu(s, j)
            assert a ^ b == 1 << s and 0 <= tw < 32
            seen |= {a, b}
        assert len(seen) == N
    rng = np.random.RandomState(0)
    worst = 1e9
    for _ in range(50):
        x = [(int(r), int(i)) for r, i in rng.randint(-32768, 32768, size=(N, 2))]
        out, ovf = fft64(x)
        assert not ovf
        ref = np.fft.fft([complex(r, i) / 32768 for r, i in x])
        got = np.array([complex(r, i) / 32768 for r, i in out])
        sqnr = 10 * np.log10(np.sum(abs(ref) ** 2) / np.sum(abs(got - ref) ** 2))
        worst = min(worst, sqnr)
    print(f"model self-test OK; worst SQNR over 50 random frames = {worst:.1f} dB")
