# Integration-test WAVs

Sanitized WAV layouts used by `tests/test_integration.nim`. They contain no
original audio or identifying metadata.

| File | Chunk layout |
|---|---|
| `bext-before-fmt-padded.wav` | `bext` (32 B) → `fmt ` (PCM, 48 kHz, mono, 24-bit) → `PAD ` (32 B) → `data` (16 silent frames) |
| `fllr-after-fmt.wav` | `fmt ` (PCM, 44.1 kHz, mono, 16-bit) → `FLLR` (32 B) → `data` (16 silent frames) |
| `canonical-pcm16.wav` | `fmt ` (PCM, 48 kHz, mono, 16-bit) → `data` (16 silent frames) |
| `float32.wav` | `fmt ` (IEEE float, 48 kHz, mono, 32-bit) → `data` (16 silent frames) |
| `broken.wav` | Truncated `bext-before-fmt-padded.wav` |
| `invalid-fmt.wav` | PCM with inconsistent `nBlockAlign`/`nAvgBytesPerSec` |

All filler/metadata payloads are zero-filled; audio is generated silence.
Filler sizes are reduced from the originals to keep the WAVs tiny.
