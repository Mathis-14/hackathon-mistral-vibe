# Vibe Work bridge — investigation (2026-07-18)

Question: can Vibe Buddy open a local Vibe Code session in the Vibe Code Web
app ("Vibe Work" / chat.mistral.ai), or list cloud agents?

Source audited: the Mistral Vibe CLI clone at
`../mistral-vibe` (version 2.21.0, `pyproject.toml:3`) — same version as the
installed binary (`vibe --version` → 2.21.0), so every code path cited below
is the code that actually runs on this machine. All file:line references are
into that clone.

## Verdict

**YES — a safe ~30-minute path exists and is implemented.** The CLI ships a
hidden, fully non-interactive teleport mode: `vibe -p "<prompt>" --teleport
--trust` creates a cloud session and prints its URL as the last stdout line.
Vibe Buddy just spawns the CLI and opens the URL — no HTTP, no auth, no keys
in the app. Helper: `app/leanring-buddy/VibeWorkTeleporter.swift` (standalone,
nothing else touched; the synced-folder Xcode project picks it up with zero
pbxproj edits).

## Mechanism (how /teleport works)

1. **Command surface**
   - Interactive slash command `/teleport` (`vibe/cli/commands.py:110-115`,
     gated on `vibe_code_enabled`, default `True` at
     `vibe/core/config/vibe_schema.py:280`), and `/remote-project` to pick the
     cloud project (`commands.py:116-121`).
   - **Hidden CLI flag** `--teleport` (`argparse.SUPPRESS`,
     `vibe/cli/entrypoint.py:151-152`). With `-p` it triggers headless
     teleport (`vibe/cli/cli.py:272-306`); without `-p` it runs `/teleport`
     on TUI startup (`cli.py:359`, `vibe/cli/textual_ui/app.py:449,939`).
     Verified present in the installed 2.21.0: `vibe --teleport --help`
     exits 0.

2. **Project resolution (headless)** — `cli.py:229-250` →
   `resolve_project_for_headless_teleport`
   (`vibe/core/vibe_code_project/picker_service.py:293-360`): use the saved
   repo→project link if any, else match the repo URL against
   `GET {base}/api/v1/code/projects`
   (`vibe/core/vibe_code_project/client.py:115-149`), else **create a new
   project** (`POST /api/v1/code/projects`, `client.py:151-156`). The link is
   persisted to `~/.vibe/projects.toml`
   (`vibe/core/paths/_vibe_home.py:36`,
   `vibe/core/vibe_code_project/project_store.py:18-33` — fields: repo_root,
   repo_url, project_id, project_name).

3. **Session creation** — `TeleportService.execute`
   (`vibe/core/teleport/teleport.py:114-171`): requires a non-empty prompt, a
   **GitHub** remote (`vibe/core/teleport/git.py:65-94`,
   `_find_github_remote`) and a checked-out branch; fetches, verifies
   commit+branch are pushed; packs the working diff as zstd+base64 (≤1 MB,
   `teleport.py:230-239`); then `POST {base}/api/v1/code/sessions`
   (`vibe/core/teleport/nuage.py:144-153`) with body
   `{projectId, source:"vibe_code_cli", idempotencyKey, message, context}`
   (`nuage.py:66-73`). Response (`nuage.py:83-91`):
   `{sessionId, webSessionId, projectId, status, url}`.

4. **Auth** — `Authorization: Bearer <key>` (`nuage.py:138-142`); the key is
   `MISTRAL_API_KEY` from the environment, falling back to the **macOS
   keyring** (`vibe_schema.py:281-283,367-369`,
   `vibe/core/config/_settings.py:103-110`,
   `vibe/core/utils/keyring.py:156+`). Base URL:
   `vibe_code_sessions_base_url = "https://chat.mistral.ai"`
   (`vibe_schema.py:336-338`).

5. **URL output** — in `-p --output text` (the default) the
   `TeleportCompleteEvent.url` becomes the formatter's final response
   (`vibe/core/output_formatters.py:64-65`) which the CLI prints as the
   **last stdout line** (`cli.py:313-314`). In the TUI it renders as the
   clickable link (`app.py:2645-2646`; CHANGELOG.md:112 "Teleport URL in the
   CLI is now clickable").

## Answers to the three questions

- **(a) URL shape:** `https://chat.mistral.ai/code/<projectId>/<webSessionId>`
  (fixture `tests/constants.py:30`:
  `https://chat.example.com/code/project-id/web-session-id`; base URL from
  `vibe_schema.py:336`). The URL is **server-minted** — `webSessionId` only
  exists after the POST, so it is *not* derivable locally for an existing
  local session. There is no "open existing local session in the cloud"
  either: teleport always creates a *new* cloud session seeded with the
  repo state + prompt (optionally a context summary,
  `vibe/core/agent_loop/_loop.py:968-1000`).
- **(b) Non-interactive trigger:** **yes** —
  `vibe -p "<prompt>" --teleport --trust` (hidden flag). Headless mode even
  auto-approves the push step (`vibe/core/programmatic.py:80-90`:
  `TeleportPushResponseEvent(approved=True)`). Exit 0 + URL on stdout;
  errors go to stderr with exit 1 (`cli.py:308-320`).
- **(c) Local record of the cloud URL:** **no.** `SessionLogger` is injected
  into `TeleportService` but never used (`teleport.py:54` is the only
  reference) — the URL is never written to `~/.vibe/logs/session/*`. The only
  local artifact is `~/.vibe/projects.toml` (project id, not the session
  URL). So "read a file after teleport" is not a viable bridge; capturing
  stdout of the headless command is the only local way to get the URL.

## Cloud agent listing (secondary)

`GET https://chat.mistral.ai/api/v1/code/projects` with
`Authorization: Bearer $MISTRAL_API_KEY` lists cloud **projects** (id, name,
linked repositories, read-only flag — `client.py:115-149,25-66`). Read-only
and cheap, usable later for a "cloud projects" strip. No endpoint for listing
cloud *sessions* exists anywhere in the CLI codebase, so a cloud-agents list
equivalent to the local sessions strip is not buildable from what the CLI
exposes today.

## Feasibility + caveats for the 30-min integration

Implemented as `VibeWorkTeleporter.swift`: spawn
`vibe -p <prompt> --teleport --trust` in the project directory, parse the
last URL-looking stdout line, hand it to the caller / open it in the browser.
Auth rides on the CLI's own env/keyring resolution — zero keys in the app
(AGENTS.md MUST #1 holds).

Caveats the integrator must know:

- **Side effects are real:** headless teleport auto-pushes unpushed commits
  on the current branch (`programmatic.py:86-89`) and creates a cloud
  session that starts a cloud agent on the prompt (account compute). First
  run against a repo may also create a Vibe Code Web project. Demo from a
  sacrificial repo.
- **Preconditions:** git repo with a **GitHub** remote (`git.py:65-70` —
  non-GitHub remotes are rejected), checked-out branch, `MISTRAL_API_KEY`
  resolvable (env or keyring — the keyring path means the app inherits the
  user's `vibe` login for free), working diff ≤ 1 MB compressed.
- **Latency:** git fetch + optional push + HTTP with up to 3 retries
  (`nuage.py:147-167`) — seconds, not ms; the helper runs it off the main
  thread with a 180 s watchdog.
- **No live teleport was executed during this investigation** (cost/side
  effects unverified per the hackathon rule; a sandboxed dry-run was also
  blocked by the environment). Verified instead: source paths above, flag
  acceptance on the installed binary, and version parity clone↔binary. The
  one-line pre-demo check, from a repo you are willing to push:
  `vibe -p "Say hi" --teleport --trust` → last line must be a
  `https://chat.mistral.ai/code/...` URL (costs one cloud session).
