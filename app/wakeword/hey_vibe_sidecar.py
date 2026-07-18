#!/usr/bin/env python3
"""Hey Vibe wake-word sidecar.

Listens to the default microphone (16 kHz mono) and prints one line "WAKE"
on stdout every time the custom openWakeWord model fires above threshold.
The Swift app (WakeWordSidecarMonitor) spawns this process and reacts to
the lines; stdout is the ONLY contract, stderr is for humans.

Requires hey_vibe.onnx AND hey_vibe.onnx.data next to this script (the
ONNX export stores its weights in the external .data sidecar).

Usage:
    .venv/bin/python hey_vibe_sidecar.py [--threshold 0.5] [--cooldown 2.0]
"""

from __future__ import annotations

import argparse
import queue
import sys
import time
from pathlib import Path

import numpy as np
import sounddevice as sd

import openwakeword
from openwakeword.model import Model

CHUNK = 1280  # 80 ms at 16 kHz — openWakeWord's native step
SAMPLE_RATE = 16_000


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--threshold", type=float, default=0.5)
    parser.add_argument("--cooldown", type=float, default=2.0)
    args = parser.parse_args()

    model_path = Path(__file__).parent / "hey_vibe.onnx"
    if not model_path.exists():
        log(f"FATAL: model not found at {model_path}")
        sys.exit(2)
    if not model_path.with_suffix(".onnx.data").exists():
        log("FATAL: hey_vibe.onnx.data missing next to the model (external weights)")
        sys.exit(3)

    # Feature models (melspectrogram + embedding) auto-download on first run.
    openwakeword.utils.download_models(["melspectrogram", "embedding"])
    model = Model(wakeword_models=[str(model_path)], inference_framework="onnx")
    model_key = list(model.models.keys())[0]

    audio_queue: queue.Queue[np.ndarray] = queue.Queue(maxsize=64)

    def on_audio(indata, _frames, _time_info, status) -> None:
        if status:
            log(f"audio status: {status}")
        try:
            audio_queue.put_nowait(indata[:, 0].copy())
        except queue.Full:
            pass  # drop under backpressure; wake words repeat anyway

    last_fire = 0.0
    with sd.InputStream(
        samplerate=SAMPLE_RATE,
        channels=1,
        dtype="int16",
        blocksize=CHUNK,
        callback=on_audio,
    ):
        print("READY", flush=True)
        log(f"listening (threshold={args.threshold}, cooldown={args.cooldown}s)")
        while True:
            chunk = audio_queue.get()
            score = model.predict(chunk)[model_key]
            now = time.monotonic()
            if score >= args.threshold and (now - last_fire) >= args.cooldown:
                last_fire = now
                print("WAKE", flush=True)
                log(f"wake fired (score={score:.3f})")
                model.reset()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
