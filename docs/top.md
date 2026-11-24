# FFT64: Top Wrapper

A tabular description of the parameters, input ports and output ports ofS the top level wrapper.

### Parameter (`fft64_top`)

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `HEX_FILE` | `string` | `"twiddle.hex"` | Path to hex file containing `Q2.14` twiddle factors |

*(Note: `IN_W` and `DW` are imported via `fft_pkg::*`.)*

---

### Input / Output Ports (`fft64_top`)

| Port | Direction | Width | Fixed-Point / Polarity | Description |
| --- | --- | --- | --- | --- |
| `clk` | `input` | 1 | Rising edge | System clock |
| `rst_n` | `input` | 1 | Active-low (synchronous) | Resets accelerator state and control logic |
| `in_valid` | `input` | 1 | Active-high | Asserted when input sample on `in_re`/`in_im` is valid |
| `in_ready` | `output` | 1 | Active-high | Indicates wrapper is ready to accept an input sample |
| `in_re` | `input` | 16 | Signed (`Q1.15`) | Real component of input sample |
| `in_im` | `input` | 16 | Signed (`Q1.15`) | Imaginary component of input sample |
| `out_valid` | `output` | 1 | Active-high | Asserted when output bin on `out_re`/`out_im` is valid |
| `out_ready` | `input` | 1 | Active-high | Downstream ready signal for accepting output bins |
| `out_re` | `output` | 23 | Signed (`Q8.15`) | Real component of output FFT bin |
| `out_im` | `output` | 23 | Signed (`Q8.15`) | Imaginary component of output FFT bin |
| `out_last` | `output` | 1 | Active-high | Asserted on the final (64th) output bin of a frame |
| `ovf` | `output` | 1 | Active-high | Overflow indicator flag |

## Interface (valid/ready)
`in_valid/in_ready/in_re/in_im` (64 samples per frame, natural order) ->
`out_valid/out_ready/out_re/out_im/out_last` (bins 0..63, natural order). Synchronous
active-low `rst_n`. A frame is: load 64 -> compute -> unload 64 (no frame overlap).