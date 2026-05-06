# OpenClaw Control Center Project
Date: 2026-05-04

## Purpose
A custom management console built as a replacement for the OpenClaw Desktop app (which was suffering from a persistent white-screen rendering bug). The goal is to provide a simplified, visual interface for managing OpenClaw configuration and gateway state without manual JSON editing.

## Architecture
- **Backend Logic**: `C:\Users\Reno\.openclaw\workspace\lib\config_manager.ts`
  - Handles deep-merging updates into `openclaw.json`.
  - Manages model aliases and primary model switching.
- **UI Layer**: `C:\Users\Reno\.openclaw\canvas\control_center.html`
  - A Canvas-based dashboard providing a Control UI for:
    - Gateway state (Restart, Stop).
    - Model selection and sandbox toggles.
    - API key/Token management (Ollama, Nvidia, Gateway).
    - Advanced flags (Device Auth, Insecure Auth, Tailscale).

## Implementation Status
- [x] Core logic implemented in `config_manager.ts`.
- [x] UI shell created in `control_center.html`.
- [ ] Full integration of UI actions to the agent's tool-call bridge.

## Context for Recovery
If the session is lost, refer to the files in `C:\Users\Reno\.openclaw\workspace\lib\` and `C:\Users\Reno\.openclaw\canvas\` to restore the management console.
