#!/usr/bin/env bash
# THE demo-path smoke. Run after EVERY change. Requires `wrangler dev`
# running (cd worker && npx wrangler dev). Defaults to replay mode;
# `DEMO_MODE=live bash scripts/smoke.sh` exercises the real Mistral API
# (costs credits) via the worker's x-demo-mode header override.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${WORKER_URL:-http://127.0.0.1:8787}"
MODE="${DEMO_MODE:-replay}"

fail() { echo "❌ SMOKE FAIL: $*" >&2; exit 1; }
pass() { echo "✅ $*"; }

# Reassemble the reply from the APP-wire SSE (data:{"type":"delta"} …
# data:{"type":"done"}) on stdin. Fails if the done terminator is missing.
app_sse_text() {
  python3 -c '
import json, sys
text, done = "", False
for line in sys.stdin:
    line = line.strip()
    if not line.startswith("data: "):
        continue
    payload = line[6:]
    if payload == "[DONE]":
        done = True
        continue
    try:
        obj = json.loads(payload)
    except json.JSONDecodeError:
        continue
    if obj.get("type") == "delta":
        text += obj.get("text", "")
    elif obj.get("type") == "done":
        done = True
if not done:
    print("missing {\"type\":\"done\"} terminator", file=sys.stderr)
    sys.exit(1)
print(text)
'
}

# Reassemble the full reply text from an SSE body on stdin.
sse_text() {
  python3 -c '
import json, sys
text = ""
for line in sys.stdin:
    line = line.strip()
    if not line.startswith("data: "):
        continue
    payload = line[6:]
    if payload == "[DONE]":
        continue
    try:
        obj = json.loads(payload)
    except json.JSONDecodeError:
        continue
    if obj.get("type") == "content_block_delta" and obj.get("delta", {}).get("type") == "text_delta":
        text += obj["delta"].get("text", "")
print(text)
'
}

echo "== smoke ($MODE mode) against $BASE"

echo "-- typecheck"
(cd "$ROOT/worker" && npx tsc --noEmit) || fail "tsc --noEmit"
pass "typecheck"

echo "-- health"
curl -fsS "$BASE/health" | grep -q '"ok":true' || fail "/health (is wrangler dev running?)"
pass "/health"

echo "-- /chat basic (stream)"
BODY='{"stream":true,"max_tokens":1024,"messages":[{"role":"user","content":"Give me a quick standup summary for today."}]}'
RAW=$(curl -fsS -N -H "x-demo-mode: $MODE" -H 'content-type: application/json' -d "$BODY" "$BASE/chat")
echo "$RAW" | grep -q '"type":"content_block_delta"' || fail "basic: no content_block_delta events"
TEXT=$(echo "$RAW" | sse_text)
[ -n "$TEXT" ] || fail "basic: empty reassembled text"
pass "/chat basic — ${#TEXT} chars"

echo "-- /chat screenshot (stream, image attached)"
python3 -c '
import base64, json, sys
img = base64.b64encode(open(sys.argv[1], "rb").read()).decode()
body = {
    "stream": True, "max_tokens": 1024,
    "messages": [{"role": "user", "content": [
        {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": img}},
        {"type": "text", "text": "Screen 1 (image dimensions: 800x500 pixels)"},
        {"type": "text", "text": "What am I looking at? Anything to fix before I send it?"},
    ]}],
}
json.dump(body, open(sys.argv[2], "w"))
' "$ROOT/fixtures/screenshot.jpg" /tmp/vb-smoke-image.json
RAW=$(curl -fsS -N -H "x-demo-mode: $MODE" -H 'content-type: application/json' --data @/tmp/vb-smoke-image.json "$BASE/chat")
TEXT=$(echo "$RAW" | sse_text)
[ -n "$TEXT" ] || fail "screenshot: empty reassembled text"
pass "/chat screenshot — ${#TEXT} chars"

echo "-- /chat actuation (stream, expects trailing [OPEN_APP:] token)"
BODY='{"stream":true,"max_tokens":1024,"messages":[{"role":"user","content":"Open Notes and get me started on the demo script."}]}'
RAW=$(curl -fsS -N -H "x-demo-mode: $MODE" -H 'content-type: application/json' -d "$BODY" "$BASE/chat")
TEXT=$(echo "$RAW" | sse_text)
echo "$TEXT" | python3 -c '
import re, sys
text = sys.stdin.read().strip()
if not re.search(r"\[(OPEN_APP|OPEN_URL):[^\]]+\]$", text):
    print(f"no trailing action token. Tail: ...{text[-120:]!r}", file=sys.stderr)
    sys.exit(1)
' || fail "actuation: reply does not END with [OPEN_APP:...] / [OPEN_URL:...]"
pass "/chat actuation — token present at end"

echo "-- /chat non-streaming"
BODY='{"stream":false,"max_tokens":1024,"messages":[{"role":"user","content":"Give me a quick standup summary for today."}]}'
curl -fsS -H "x-demo-mode: $MODE" -H 'content-type: application/json' -d "$BODY" "$BASE/chat" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["content"][0]["text"], "empty text"' \
  || fail "non-streaming /chat"
pass "/chat non-streaming"

echo "-- /chat APP wire basic (screenshot_base64:null — the shipped Swift client's shape)"
BODY='{"messages":[{"role":"user","content":"Give me a quick standup summary for today."}],"screenshot_base64":null}'
RAW=$(curl -fsS -N -H "x-demo-mode: $MODE" -H 'content-type: application/json' -d "$BODY" "$BASE/chat")
echo "$RAW" | grep -q '"type":"delta"' || fail "app basic: no delta events"
TEXT=$(echo "$RAW" | app_sse_text) || fail "app basic: bad stream (no done terminator?)"
[ -n "$TEXT" ] || fail "app basic: empty reassembled text"
pass "/chat app basic — ${#TEXT} chars, done terminator present"

echo "-- /chat APP wire screenshot (screenshot_base64 attached)"
python3 -c '
import base64, json, sys
img = base64.b64encode(open(sys.argv[1], "rb").read()).decode()
body = {
    "messages": [{"role": "user", "content": "What am I looking at? Anything to fix before I send it?"}],
    "screenshot_base64": img,
}
json.dump(body, open(sys.argv[2], "w"))
' "$ROOT/fixtures/screenshot.jpg" /tmp/vb-smoke-app-image.json
RAW=$(curl -fsS -N -H "x-demo-mode: $MODE" -H 'content-type: application/json' --data @/tmp/vb-smoke-app-image.json "$BASE/chat")
TEXT=$(echo "$RAW" | app_sse_text) || fail "app screenshot: bad stream"
[ -n "$TEXT" ] || fail "app screenshot: empty reassembled text"
pass "/chat app screenshot — ${#TEXT} chars"

echo "-- /chat APP wire actuation (expects trailing [OPEN_APP:] token)"
BODY='{"messages":[{"role":"user","content":"Open Notes and get me started on the demo script."}],"screenshot_base64":null}'
RAW=$(curl -fsS -N -H "x-demo-mode: $MODE" -H 'content-type: application/json' -d "$BODY" "$BASE/chat")
TEXT=$(echo "$RAW" | app_sse_text) || fail "app actuation: bad stream"
echo "$TEXT" | python3 -c '
import re, sys
text = sys.stdin.read().strip()
if not re.search(r"\[(OPEN_APP|OPEN_URL):[^\]]+\]$", text):
    print(f"no trailing action token. Tail: ...{text[-120:]!r}", file=sys.stderr)
    sys.exit(1)
' || fail "app actuation: reply does not END with an action token"
pass "/chat app actuation — token present at end"

echo "-- /transcribe"
curl -fsS -H "x-demo-mode: $MODE" -F "file=@$ROOT/fixtures/voice-sample.wav;type=audio/wav" -F "model=ignored-by-worker" "$BASE/transcribe" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("text","").strip(), "empty transcript"; print("   transcript:", d["text"])' \
  || fail "/transcribe"
pass "/transcribe"

if [ "$MODE" = "live" ]; then
  echo "-- live-mode source check (no silent fixture fallback)"
  SRC=$(curl -fsS -D - -o /dev/null -H "x-demo-mode: live" -H 'content-type: application/json' \
    -d '{"stream":false,"max_tokens":64,"messages":[{"role":"user","content":"Say OK."}]}' "$BASE/chat" \
    | tr -d '\r' | awk -F': ' 'tolower($1)=="x-vibe-source"{print $2}')
  [ "$SRC" = "live" ] || fail "expected x-vibe-source: live, got: '$SRC' (fixture fallback kicked in?)"
  pass "served live"
fi

echo "== SMOKE GREEN ($MODE)"
