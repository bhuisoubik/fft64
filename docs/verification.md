# Verification

## Testbenches

- `tb_twiddle_rom`, `tb_cmul` (rounding corners, extreme values), `tb_butterfly`
- `tb_agu`: every index is visited exactly once per stage, and A/B/twiddle match Python
- `tb_fft64` is the system test. It is file-driven: it reads `input.hex`, writes `output.hex`, and dumps a **memory snapshot after each stage** for localizing mismatches.
- SVA checks: output stable while `out_valid && !out_ready`, no `in_ready` outside LOAD, the overflow shadow-sum assertion, and a latency check.
- Random backpressure on both the input and output sides in at least one test mode.

**Directed frames:** impulse (at 0 and at a non-zero position), DC, on-bin tone, off-bin tone, Nyquist, a worst-case sign-pattern frame (the ≈81 and ≈90 growth cases), all-max, and all-min (−1.0). Then constrained-random frames with the seed logged.

## Golden Model

- `gen_twiddle.py` is the single source for `twiddle.hex`.
- `gen_vectors.py` produces the input frames.
- `fft_model.py` is the bit-accurate model. It mirrors the RTL stage by stage, with the same bit-reversal, rounding, and widths, and can emit per-stage snapshots.
- `compare.py` has two checks:
  - **Pass/fail:** zero mismatches against the fixed-point model, reporting the first mismatch as (frame, stage, index).
  - **Note:** `numpy.fft` is called on the quantized inputs, giving SQNR and max error per frame.
- A `Makefile` ties it together (Verilator, plus Python).

## Run

`make test` runs everything, and `make lint` runs Verilator `-Wall` on the RTL.