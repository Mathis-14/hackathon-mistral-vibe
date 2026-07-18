# Contrat d'intégration Vibe ↔ Orchestral (résultats du spike, vibe 2.21.0)

Vérifié le 18/07/2026 sur la machine de démo. C'est LA référence pour
FleetManager / SessionWatcher / VibeConfigReader — ne pas deviner, tout est ici.

## 1. Spawn d'un agent de flotte

```bash
vibe -p "<tâche>" \
  --output streaming \
  --trust \                    # OBLIGATOIRE en non-interactif (skip le trust prompt)
  --auto-approve \             # approuve tous les tool calls
  --max-turns 25 \
  --max-price 1.0 \
  [--worktree <nom>] \         # worktree git auto (create-or-reuse)
  [--agent <nom>] \            # défaut: default_agent de la config
  [--workdir <dir>]
```

- stdout = **NDJSON, 1 message par ligne** (voir §2). stderr = vide en marche normale.
- exit 0 = terminé ; ≠0 = erreur. Pas d'événement "done" : la fin du process fait foi.
- Kill propre : SIGTERM au process group.
- Relance/réponse : `vibe --resume <SESSION_ID> -p "<instruction>" --output streaming --trust --auto-approve`

## 2. Schéma NDJSON (streaming)

Chaque ligne = un LLMMessage :

```jsonc
{
  "role": "system" | "user" | "assistant" | "tool",
  "content": "…",                    // texte (résultat d'outil pour role=tool)
  "reasoning_content": "…" | null,   // thinking (assistant)
  "tool_calls": [                    // assistant uniquement, sinon null
    { "id": "D1M0XnrX5", "index": 0, "type": "function",
      "function": { "name": "read_file", "arguments": "{…json str…}" } }
  ],
  "name": "read_file" | null,        // role=tool : nom de l'outil
  "tool_call_id": "…" | null,        // role=tool : corrèle avec tool_calls[].id
  "message_id": "uuid", "reasoning_message_id": "uuid" | null,
  "images": null, "injected": false, "user_display_content": null
}
```

Mapping état FleetManager :
- `queued` → process pas encore lancé
- `running` → process vivant ; `lastToolAction` = dernier `tool_calls[0].function.name`
  (ou `name` du role=tool) ; sparkline = timestamps des messages role=tool
- `done` → exit 0 ; le résumé = dernier message assistant sans tool_calls
- `error` → exit ≠ 0 (ou NDJSON invalide prolongé)
- `needs_input` → **PAS de ask_user_question en mode -p (outil retiré, vérifié)**.
  Détection : exit 0 MAIS dernier assistant se termine par une question / dit
  qu'il lui manque une info. Heuristique v1 : content final contient "?" dans la
  dernière phrase → badge "💬 réponse attendue". La réponse du popover relance
  avec `--resume <session_id>` (§3).

Tools visibles en -p : bash, edit, grep, read_file, skill, task, todo,
web_fetch, web_search, write_file (filtrables par --enabled-tools/--disabled-tools).

## 3. Sessions sur disque (SessionWatcher)

Répertoire : **`~/.vibe/logs/session/session_YYYYMMDD_HHMMSS_<hash8>/`**
(toutes les sessions : interactives TTY, -p, ET subagents)

- `meta.json` :
  ```jsonc
  {
    "session_id": "7098a039-…",          // ← pour --resume
    "parent_session_id": null,            // non-null = subagent d'une session
    "start_time": "…+00:00", "end_time": "…" | null,
    "git_commit": "…", "git_branch": "master",
    "environment": { "working_directory": "/…/demo-repo" },
    "title": "Read src/pricing.py and briefly…",   // titre auto → l'UI l'affiche
    "stats": {
      "steps": 3,
      "session_prompt_tokens": 12909, "session_completion_tokens": 493,
      "input_price_per_million": 1.5, "output_price_per_million": 7.5,
      "tool_calls_succeeded": 1, "tool_calls_failed": 0,
      "last_turn_duration": 3.17, "tokens_per_second": 117.3, …
    }
  }
  ```
  **Coût $** = (session_prompt_tokens × input_price_per_million
             + session_completion_tokens × output_price_per_million) / 1 000 000
- `messages.jsonl` : mêmes objets que le NDJSON §2 → tail pour l'activité live.
- Corrélation FleetManager↔session : `environment.working_directory` + start_time
  (le process est spawné juste avant la création du dossier).
- Session interactive "en attente d'input" : dernier message = assistant avec
  tool_calls `ask_user_question` sans role=tool correspondant ensuite.
- Watcher : FSEvents sur le dossier parent + re-lecture meta.json (il est réécrit
  en cours de session) ; poll léger 2 s en fallback.

## 4. Config agents (VibeConfigReader)

- `~/.vibe/config.toml` — config globale (TOML). Modèles, default_agent, etc.
- `~/.vibe/agents/*.toml` — agents custom (`agent_type = "subagent"` pour les
  subagents). Builtins non listés sur disque : default, plan, accept-edits,
  auto-approve (+ subagent builtin: explore).
- Projet : `<repo>/.vibe/config.toml` (surcharges locales).

## 5. Vibe Work (bouton "View")

`/teleport` (TUI) crée une session cloud liée au remote GitHub. Pour un process
-p il n'y a pas de commande CLI directe → v1 du bouton View : ouvrir une fenêtre
locale « transcript » (lecture de messages.jsonl, joli rendu). Si le temps le
permet : tester `vibe --resume <id>` puis `/teleport` scripté, sinon deep-link
Vibe Work manuel pour la démo.

## 6. Divers vérifiés

- vibe installé : `~/.local/bin/vibe` (2.21.0, mis à jour pendant le spike).
- Repo de démo : `demo-repo/` (3 issues plantées dans `src/pricing.py` :
  remise inversée, NameError `pricess`, TODO formatage — les tests
  `src/test_pricing.py` échouent tant que non corrigées).
- Coût du spike : ~0,02 $ / run de 3 tours. `--max-price 1.0` par agent est
  large pour la démo.
