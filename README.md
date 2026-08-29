# AUTORELOG

Dashboard & master-data controller for AutoGhostStory (AutoCycle scheduler).

## Features
- Master Data table: single source of truth for clients / groups / slots, synced to CSV and AutoCycle.
- Live DB Status with real-time group running state.
- Dynamic groups (each = 5 clients + slot), auto-pushed to the cycle.
- Public URL via ngrok.

## Setup
1. Clone repo.
2. Use clients_master.json / clients_master.csv as master data.
3. Provide your own config.json (emulator/API tokens) and ngrok token - these are NOT committed (see .gitignore).
4. Run serve.ps1 and open db.html.

## Files
- db.html - dashboard UI
- serve.ps1 - local HTTP server + master API
- sync_master.ps1 - regenerate config/db from master
- AutoCycle.ps1 - scheduler daemon
- clients_master.json / clients_master.csv - master data
