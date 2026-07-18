#!/usr/bin/env python3
"""Reference mock of the worker contract (app/CHAT_CONTRACT.md) — stdlib only.

Serves the two routes the app consumes, with the exact shapes the Swift
parsers expect. Useful to exercise the FULL app loop (voice included) before
the real worker exists, and as a living test vector for the worker build.

    python3 app/scripts/mock_worker.py     # listens on 127.0.0.1:8787
"""

import json
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

CHAT_REPLY = (
    "Voxtral heard you loud and clear — this is the MOCK worker answering. "
    "Your screenshot came through as well. Let me open Notes so you can jot "
    "the plan down. [OPEN_APP:Notes] When the real worker lands, this exact "
    "flow switches to Mistral Medium with zero app changes."
)

TRANSCRIBE_REPLY = {"text": "Open Notes and get me started on the pricing fix"}


class MockWorkerHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path == "/chat":
            self.handle_chat(body)
        elif self.path == "/transcribe":
            self.handle_transcribe(body)
        else:
            self.send_error(404, "unknown route")

    def handle_chat(self, body: bytes) -> None:
        try:
            payload = json.loads(body)
            has_screenshot = bool(payload.get("screenshot_base64"))
            n_messages = len(payload.get("messages", []))
        except (json.JSONDecodeError, AttributeError):
            self.send_error(400, "invalid JSON body")
            return

        print(f"[mock] /chat — {n_messages} message(s), screenshot={'yes' if has_screenshot else 'no'}")
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()

        for word in CHAT_REPLY.split(" "):
            event = json.dumps({"type": "delta", "text": word + " "})
            self.wfile.write(f"data: {event}\n\n".encode())
            self.wfile.flush()
            time.sleep(0.04)
        self.wfile.write(b'data: {"type": "done"}\n\n')
        self.wfile.flush()

    def handle_transcribe(self, body: bytes) -> None:
        print(f"[mock] /transcribe — received {len(body)} bytes of audio multipart")
        response = json.dumps(TRANSCRIBE_REPLY).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)

    def log_message(self, format, *args):  # quieter default logging
        pass


if __name__ == "__main__":
    print("[mock] worker contract mock on http://127.0.0.1:8787 (/chat + /transcribe)")
    HTTPServer(("127.0.0.1", 8787), MockWorkerHandler).serve_forever()
