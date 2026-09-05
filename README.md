# AUTORELOG

AutoGhostStory (AutoCycle) client manager — discovery, runtime state, master data, scheduler model.

## Status
- **Phase 0 HAR Discovery: COMPLETED** (see `phase0.md`, `dulieu`).
- **Phase 0 PC Validation: PENDING** — gates B1/B2/B3/B7 require live PC + Remote WebSocket tests before any production control is enabled.
- No gameplay automation. Client-level control is captured/validated, not assumed.

## Architecture (3 layers — plan v4 §4)
```
MASTER   client_id / name / group / policy / schedule   (clients_master.json)
RUNTIME  client_id / state / cap / lastSeen              (scr_list_res -> runtime_registry.json)
CONTROL  computed desiredState / requestId / action      (Agent v1, future)
```
`desiredState` is computed/read-only: `fixed`=running, `none`=ignore, `orphan`=blocked, `scheduled`=from group window.

## Files
- `clients_master.json` — canonical configuration (generated from `lich trinh tat mo.xlsx` + runtime). Source of truth.
- `AUTORELOG.Core.psm1` — pure 3-layer logic (policy, schedule windows, desiredState, reconcile, validate, key mapping). No network.
- `Validate-Master.ps1` — validates `clients_master.json` (B4 wraparound, group conflict, orphan hard-block).
- `Sync-Discovery.ps1` — reconciles master <-> runtime snapshot into `runtime_registry.json` + `discovery_report.txt`.
- `B1-B7-Validate.ps1` — emits `phase0_gate_report.json` (Phase 0 gates).
- `scr_list_sample.json` — sample `scr_list_res` snapshot for offline testing.
- `plan` / `phase0.md` / `dulieu` / `phản hồi` — plan + evidence + review.
- `plan_addendum.md` — feedback integration + current status.

## Setup
1. Clone repo.
2. Provide your own `config.json` (Remote session/token) — NOT committed (see `.gitignore`).
3. `clients_master.json` is committed (safe, no secrets). Edit via the XLSX pipeline (B4) or directly.
4. Run: `powershell -File Validate-Master.ps1` then `powershell -File Sync-Discovery.ps1`.

## Security
- Remote credentials live ONLY in `config.json` (gitignored). `remote.txt` is a redacted pointer — rotate that password.
- Any future control API (Agent/Dashboard) MUST require auth (shared-secret header) before exposure via ngrok/public URL (see `plan_addendum.md`).
- Never commit HAR, cookie, session token, or password. Scrub before sharing.
