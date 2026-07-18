# « Hey Vibe » wake word (v2 stretch)

Custom openWakeWord model (trained 2026-07-18 on Colab H100, 59 real
recordings + 2000 synthetic positives, ESC-50 noise). Eval @0.5:
recall 0.72 (synthetic), false-trigger 0/300 on ESC-50.

## Files

- `hey_vibe_sidecar.py` — mic listener, prints `WAKE` on stdout (the app's contract)
- `hey_vibe.onnx` + `hey_vibe.onnx.data` — the model (BOTH files required:
  the weights live in the external `.data` sidecar)
- `.venv/` — local Python env (not committed)

## Setup (once per machine)

```bash
cd app/wakeword
uv venv .venv && VIRTUAL_ENV=$PWD/.venv uv pip install openwakeword onnxruntime sounddevice numpy scipy
.venv/bin/python hey_vibe_sidecar.py   # says READY, then WAKE on "Hey Vibe!"
```

The app (WakeWordSidecarMonitor) auto-starts the sidecar when this
directory, the venv and both model files exist. Override the directory with
`defaults write com.vibebuddy.app vibebuddy.wakewordDir <path>`; disable with
`defaults write com.vibebuddy.app vibebuddy.wakeword -bool false`.
Demo tip: raise the threshold in a noisy room by editing the spawn args
(`--threshold 0.7`) in WakeWordSidecarMonitor.swift.
