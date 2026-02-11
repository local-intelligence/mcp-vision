# MCP Vision v0.1 Specification (Static Images)

Version: v0.1  
Status: Draft  
Repo: local-intelligence/mcp-vision  
Primary goal: Provide an MCP server that can capture **static snapshots** from a locally attached webcam, with explicit safety gating and auditability.

---

## 1. Scope

### 1.1 In scope (v0.1)
- A local MCP server that exposes a **single-shot image capture** capability (“snapshot”).
- **Explicit ARM/DISARM** gate:
  - When **DISARMED**, all camera operations are denied.
  - When **ARMED**, snapshots are allowed subject to policy.
- **Audit logging** for every sensitive request (allowed or denied).
- Local-only defaults:
  - Bind to `127.0.0.1` by default.
  - No remote access by default.
- Webcam selection by index/name (best-effort, platform dependent).
- Return image bytes as base64 (or MCP-native binary equivalent) and minimal metadata.

### 1.2 Explicit non-goals (v0.1)
- No video streaming (RTSP/WebRTC/UVC streaming mode).
- No continuous capture / frame subscription.
- No PTZ control (may be stubbed as a future tool surface).
- No microphone/audio capture (reserved for v0.2+).
- No remote auth / multi-user accounts.
- No background “always on” capture. Snapshot is strictly request-driven.

---

## 2. Safety model (trust boundary)

### 2.1 Principles
- **Local-first**: control and gating decisions happen locally.
- **Explicit consent**: the server starts DISARMED and must be explicitly ARMED.
- **Least privilege**: only minimal tools are exposed for v0.1.
- **Auditability**: every sensitive action is logged with a stable event schema.
- **Fail closed**: on any ambiguity or error, deny the operation.

### 2.2 ARM/DISARM state machine
- Default state on startup: **DISARMED**
- State transitions:
  - `arm()` transitions DISARMED → ARMED
  - `disarm()` transitions ARMED → DISARMED
- When DISARMED:
  - `capture_image` must return a deterministic error (`ERR_DISARMED`)
- When ARMED:
  - `capture_image` may proceed
- Optional: auto-disarm timer (recommended but may be deferred to v0.2)
  - If implemented in v0.1: default OFF unless configured.

### 2.3 Local-only defaults
- Server binds to `127.0.0.1` unless explicitly configured.
- If a non-loopback bind is requested, the server should:
  - require an explicit `--allow-nonlocal` flag (or config)
  - emit a prominent warning on startup
  - still enforce ARM/DISARM and auditing

---

## 3. Public interface

### 3.1 MCP tools
The server exposes these MCP tools:

#### 3.1.1 `vision.get_state`
Returns current safety and device state.

**Output**
- `armed`: boolean
- `device`: optional object
  - `selected_camera`: string or index
  - `resolution`: optional `{ width, height }`
- `policy`: object
  - `bind`: string (e.g., `127.0.0.1:PORT`)
  - `local_only`: boolean

#### 3.1.2 `vision.arm`
Arms the server.

**Inputs**
- `reason` (string, optional): human-readable reason

**Output**
- `armed`: true

**Rules**
- Idempotent: calling `arm` when already armed is OK.
- MUST write an audit event.

#### 3.1.3 `vision.disarm`
Disarms the server.

**Inputs**
- `reason` (string, optional)

**Output**
- `armed`: false

**Rules**
- Idempotent.
- MUST write an audit event.

#### 3.1.4 `vision.capture_image`
Captures a single static image from the selected camera.

**Inputs (v0.1)**
- `format`: `"jpeg"` | `"png"` (default `"jpeg"`)
- `max_width`: integer optional (server may downscale; default none)
- `max_height`: integer optional
- `quality`: integer 1–100 optional (only for jpeg; default 85)
- `camera`: optional selector
  - `index` (int) or `name` (string) (implementation-defined)
- `purpose`: string optional (human-readable, logged)

**Outputs**
- `format`: `"jpeg"` | `"png"`
- `width`: int
- `height`: int
- `image_base64`: string (base64-encoded bytes)
- `captured_at`: RFC3339 timestamp (UTC recommended)
- `camera`: string (resolved camera identifier)
- `sha256`: hex string of raw image bytes (optional but recommended)

**Rules**
- When DISARMED: MUST return `ERR_DISARMED` and MUST audit the denial.
- When ARMED:
  - MUST audit the request (allowed)
  - MUST produce a new capture (no caching) unless explicitly configured (default: no cache)
- If capture fails: MUST return `ERR_CAPTURE_FAILED` with a stable message substring and MUST audit as failure.

---

## 4. Errors and deterministic failure modes

All errors should be:
- non-zero outcome (tool error response)
- include a stable `code`
- include a stable, assertable message substring

### 4.1 Standard error codes (v0.1)
- `ERR_DISARMED`: capture attempted while disarmed
- `ERR_INVALID_ARGUMENT`: malformed inputs (bad format, invalid quality, etc.)
- `ERR_CAMERA_NOT_FOUND`: selected camera not available
- `ERR_CAPTURE_FAILED`: camera access failed, driver error, permission, etc.
- `ERR_INTERNAL`: unexpected internal exception

### 4.2 Required error message contents
For `ERR_DISARMED`, message must include:
- `"disarmed"` and `"vision.arm"`

Example:  
`"Denied: camera is disarmed. Call vision.arm before capture."`

For `ERR_CAPTURE_FAILED`, message should include:
- `"capture failed"` and a best-effort reason (platform dependent)

---

## 5. Audit logging (required)

### 5.1 What must be logged
Every call to:
- `vision.arm`
- `vision.disarm`
- `vision.capture_image` (allowed or denied)

Additionally:
- any error outcome for these tools MUST be logged.

### 5.2 Audit event schema (JSONL recommended)
Each event is one JSON object per line.

Required fields:
- `ts`: RFC3339 timestamp
- `event`: string (e.g., `ARM`, `DISARM`, `CAPTURE_REQUEST`, `CAPTURE_DENIED`, `CAPTURE_OK`, `CAPTURE_ERROR`)
- `armed`: boolean (state at time of event)
- `tool`: string (MCP tool name)
- `request_id`: string (generated per request)
- `client`: object (best-effort)
  - `transport`: `"stdio"` | `"tcp"` | etc.
  - `peer`: string (if applicable)
- `details`: object (tool-specific)
- `result`: object
  - `ok`: boolean
  - `code`: optional error code
  - `message`: optional short message

Capture-specific `details` should include (when available):
- `format`, `quality`, `max_width`, `max_height`
- `camera` selector
- `purpose` string (if provided)
- output metadata: `width`, `height`, `sha256` (if computed)

### 5.3 Audit log location
- Default: `./logs/audit.jsonl` (relative to working directory) OR an OS-appropriate app data dir.
- Configurable via env var or CLI flag (implementation choice).

---

## 6. Configuration and runtime

### 6.1 CLI (suggested)
- `mcp-vision serve`
  - `--bind 127.0.0.1:0` (default localhost; 0 = choose port)
  - `--camera INDEX|NAME` (optional)
  - `--audit-log PATH` (optional)
  - `--allow-nonlocal` (required to bind to non-loopback)
  - `--start-armed` (default false; if true, MUST log an ARM event at startup)

### 6.2 Environment variables (optional)
- `MCP_VISION_AUDIT_LOG=/path/to/audit.jsonl`
- `MCP_VISION_BIND=127.0.0.1:PORT`

---

## 7. Security considerations (v0.1)

### 7.1 Threat model (v0.1)
We assume:
- The machine is trusted by its owner.
- The server may be invoked by an AI client (local or remote) via MCP transport.
Primary risks:
- accidental or unauthorized capture
- silent capture without user knowledge
- exfiltration of images

Mitigations in v0.1:
- default DISARMED
- explicit ARM required
- local-only bind by default
- audit log for all sensitive actions
- fail-closed behavior

### 7.2 Privacy stance
- No image is stored by default (only returned to requester).
- If any caching is implemented, it must be opt-in and documented (default OFF).

---

## 8. Testing requirements (v0.1)

Minimum tests:
- Server starts DISARMED.
- `vision.capture_image` while DISARMED:
  - returns `ERR_DISARMED`
  - audit event is written with denied outcome
- `vision.arm` then `vision.capture_image`:
  - returns an image payload (or, in test mode, a deterministic stub image)
  - audit event indicates success
- `vision.disarm` then capture:
  - denied again deterministically

Platform note:
- To keep CI stable, image capture should support a **mock camera provider** (fixture image bytes)
  controlled by env var or test-only config.

---

## 9. Roadmap pointers (not part of v0.1)

Likely v0.2 additions:
- microphone transcription tool (transcript-only, gated)
- PTZ tool surface (pan/tilt/zoom) with explicit gating + audit events
- optional auto-disarm timer
- richer policy controls (allowed hours, max captures per minute)

Likely v0.3+:
- deterministic concurrency policies
- streaming (if ever) with much stronger safety model

