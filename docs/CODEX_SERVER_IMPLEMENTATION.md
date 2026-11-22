# Creatora OBS Companion — server implementation contract (Codex)

**Status:** Specification, not an implementation. Build these APIs in the existing AATBusiness/Creatora Node.js API and account dashboard before attempting to pair the plugin. The OBS plugin is a client of these exact paths and protocol fields. Treat all inputs as hostile.

## Goals and threat model

- User identity: existing Creatora session + tenant membership. An OBS client is **not** a Creatora administrator or a Twitch OAuth user.
- Link device explicitly from the currently authenticated user's Creatora account, in a separate browser if desired.
- An attacker may intercept the pairing code, guess codes, compromise a user account, replay traffic, inspect logs, or send malformed commands; assume the internet is hostile.
- Confidentiality/integrity: require TLS 1.2+ with valid certificates on HTTPS/WSS, HSTS, do not expose an insecure `ws://` fallback, never log Authorization headers, tokens or pairing verifier, and reject token/query credential auth.
- Remote actions are high risk. Default permission **none** until the user explicitly allows each action/capability. No scripts, shells, arbitrary URLs, file operations, browser-source navigation, stream start/stop or scene collection import in v1.
- Pairing and device revocation require authenticated Creatora session, CSRF protection appropriate to session authentication, tenant membership checks and device ownership. A moderator cannot secretly register a device on another streamer.

## Base URL and endpoints

Production base URL: `https://aattest.akurosia.de` in the plugin UI (user can change it **before** pairing). WebSocket URL: `wss://aattest.akurosia.de/api/obs-companion/v1/connect`.

These routes should be added to the existing API process behind the existing Traefik routing. No separate ingress or inbound LAN port is necessary.

### 1. Begin pairing (public, rate limited)

`POST /api/obs-companion/v1/pairing/start`

Request:
```json
{"protocol":1,"challenge":"base64url(SHA256(verifier))","device_name":"OBS Studio"}
```

- `verifier` is 32 random bytes represented as unpadded base64url. The server **never** receives it at `start`.
- Validate challenge length = 43 base64url chars, version=1, device name <= 100 printable chars.
- Persist a random opaque `pairing_id` (>=128 bits), random user-facing code with >= 45 bits entropy (e.g. 10 chars of unambiguous Base32), SHA256(challenge) or challenge, created/expiry (5 min), status `pending`, attempt count. Hash the code at rest; compare in constant time. Limit per IP and prefix / device, reject excessive outstanding requests. Bind one code to exactly one pairing.
- Response `201`:
```json
{"pairing_id":"opaque-random-id","user_code":"ABCD-EFGH-JK","expires_in":300,"interval":3}
```
- `Cache-Control: no-store`; no CORS for arbitrary origins.

### 2. Approve in account dashboard (authenticated)

In **Mein Konto → OBS Companion** add input for the code and a list of paired devices with revocation and permissions. Approval requires explicit click, prominent warning: **“This device can control the permitted OBS actions while connected.”**

`POST /api/obs-companion/v1/pairing/approve` (Creatora session + CSRF)
```json
{"user_code":"ABCD-EFGH-JK","name":"My streaming PC","permissions":["scene.switch"]}
```

- Server resolves account + tenant from authenticated session **only**; ignore tenant IDs in request.
- Display requested device name + expiration prior to final confirmation.
- At most one approval; transactionally mark code approved and create `device_id` (UUIDv4/strong opaque ID), bind tenant_id, account_id, initial permission allowlist, created_by, device status active. Require account step-up authentication / reauthentication for high-risk permissions.
- Keep default permissions minimal: `scene.switch` can be enabled explicitly; `input.mute` and `sceneitem.visibility` independently opt-in. Never grant stream/recording control in v1.
- Log approval event with actor, tenant, device, time, IP (do not log code/tokens).

### 3. Poll for credentials (anonymous but proof-of-possession)

`POST /api/obs-companion/v1/pairing/poll`
```json
{"pairing_id":"opaque-random-id","verifier":"32-byte-base64url-entropy"}
```

- Before responding, validate SHA256(decoded verifier) in base64url matches stored challenge (constant-time). Strict 3-second poll rate per pairing and global IP limits.
- `202` while pending, `410` if expired/denied/redeemed, `429` for excessive polling, `200` exactly once on approved pairing.
- Return rotated/expiring credentials only to the verified poller, not the dashboard approval response. Atomically consume on first successful poll, then delete verification state and user code.
- Response `200`:
```json
{"device_id":"uuid","access_token":"opaque-access-secret","refresh_token":"opaque-refresh-secret","expires_in":600}
```
- Store only HMAC-SHA256 hashes of opaque tokens (using separate server-held pepper) or hashes of sufficiently random secret tokens. Access tokens should be device-bound, tenant-bound, scope-bound, expire <=10 minutes. Refresh tokens are independent >=256-bit random secrets; rotate on every use.

### 4. Refresh credentials

`POST /api/obs-companion/v1/device/refresh`
```json
{"device_id":"uuid","refresh_token":"opaque-refresh-secret"}
```

- On success respond `200` with fresh access_token, **new refresh_token**, `expires_in:600`.
- Transactionally rotate refresh token and revoke the old one. Detect replay/reuse; revoke the whole device token family if refresh-token theft is detected. To handle network retry after response loss without false-positive replay, use an explicitly documented brief idempotency window and request ID (requires a client update), or fail closed and prompt re-pairing. Initial plugin does not retry a refresh body in a loop by itself.
- Return 401 for revoked/invalid token, 403 for disabled device.
- Log events without credentials.
- The plugin persists these secrets with Windows DPAPI, bound to the OS login; it does not put secrets in OBS global settings or URL.

### 5. Connect OBS via WSS

`GET /api/obs-companion/v1/connect`

- Standard WebSocket upgrade and header `Authorization: Bearer <short-lived access token>`; do not accept tokens in URL or cookies as substitutes.
- Validate token, tenant/device ownership/status, allowed Origin policy (native Qt may omit Origin), enforce max 1 live connection per device, heartbeat <=30 sec, message size <=8 KiB, connection and per-tenant rate limits, connection idle cutoff. Close on revoke, policy changes or account disconnect; reconnect requires fresh token.
- Protect against connection hijacking and duplicated devices: replace or reject old socket on concurrent connection; monitor audit events.
- Plugin sends after connection:
```json
{"type":"hello","protocol":1,"device_id":"uuid","capabilities":["scene.switch","sceneitem.visibility","input.mute"]}
```
- Server validates protocol, device_id and expected capabilities; no commands until hello is accepted.

### 6. Command envelopes, validation, and receipts

Only server emits a `command` after verifying the initiating account, tenant, owner-set permission and command-specific policy. Limit to 5 actions/second/device and 100/minute/device; burst protection. Commands are **not** broadcast to all devices by default. Reject offline/expired commands.

Example server → plugin:
```json
{"type":"command","id":"c56b9b58-10c8-42b3-ace5-f0cc20dcefee","action":"scene.switch","args":{"scene":"BRB"},"expires_at_ms":1794599999000}
```

`expires_at_ms` is an **absolute Unix time in milliseconds**, maximum 30 seconds in the future. The plugin accepts only commands with valid TTL and deduplicates 512 recent IDs. If clocks are badly skewed, commands fail closed.

Supported v1 actions:

| action | args | scope |
|---|---|---|
| `scene.switch` | `{ "scene": "BRB" }` | Exact existing scene name only |
| `sceneitem.visibility` | `{ "scene":"Gameplay", "source":"Webcam", "visible":false }` | Exact scene and direct source name |
| `input.mute` | `{ "input":"Mic/Aux", "muted":true }` | Only audio-capable source |

Plugin → server result:
```json
{"type":"result","id":"c56b9b58-10c8-42b3-ace5-f0cc20dcefee","ok":true,"reason":"ok"}
```

- Never accept a `command` from arbitrary web clients without server policy enforcement; websocket bearer scope is **device**, not API admin scope.
- Track receipts and failures for dashboard observability. The plugin must **not** apply arbitrary actions not in its local allowlist, regardless of server request.
- Command ID and TTL are for replay resistance, **not cryptographic signatures**: TLS + correctly authenticated and authorized server/device connection is mandatory. If end-to-end separation from server operators is required, add signed command envelopes (Ed25519) and key management in a future protocol version.
- Do not expose general OBS scripting or call-OBS-request transport from the browser.

### 7. Revoke and device management

`GET /api/obs-companion/v1/devices` (authenticated) → list only current tenant's devices, connected/disconnected, granted permissions, last_seen, created_at.

`DELETE /api/obs-companion/v1/devices/:deviceId` (authenticated + CSRF) → revoke all device tokens and actively close socket; return 204.

`PATCH /api/obs-companion/v1/devices/:deviceId` (authenticated + CSRF) → update explicit permissions, optionally display name. Restrict grants to owner/admin; revoke disallowed queued commands immediately. For maximum safety require re-pairing to elevate permission scope.

### 8. Integration architecture for Codex

- Add migration for `obs_companion_pairings`, `obs_companion_devices`, `obs_companion_refresh_tokens`, and `obs_companion_command_audit` (or follow repo's existing DB conventions).
- Implement a device-auth service separate from Twitch OAuth. Reuse existing authenticated session and tenant authorization but NEVER store Twitch tokens in companion device rows.
- Add account UI for pairing approval, device list, permission toggles and revocation. No companion tokens or credentials shown in dashboard.
- Implement a per-tenant OBS command dispatcher called from configured bot commands, channel point actions and future automation builder; enforce tenant and device permissions at dispatch. Do not allow viewers to choose unrestricted scene names/actions: owner must configure vetted rules.
- Use existing reverse proxy host/path routing. WebSocket `Upgrade` needs to be forwarded by the current proxy; no new hostname/port.
- Add integration tests for unauthenticated approval, guessed codes, cross-tenant approval, forged pairing verifier, two approval attempts, double poll, token rotation replay, revoked socket, permission elevation, command ID replay and expired commands.
- Return structured error objects with stable code names, but do not expose existence of users/tenant/device to unauthenticated parties.
- Maintain compatibility with the plugin version 1 protocol above. If the contract is changed, coordinate matching OBS plugin changes.

## Operational notes

- Strict TLS certificate validation must be enabled at the application endpoint and on the client. Do not disable `verifyPeer` in any environment.
- Rotate signing/encryption/pepper keys with planned overlap and revocation policy. Restrict DB access and use encrypted backups.
- Keep logs of denied requests, authorized dispatches and device revocations without credential values.
- Assume physical compromise or malicious OBS plugins can access the streaming PC; DPAPI is not a substitute for protecting the local account.
- *Do not deploy v1 as production-ready before security review, successful native Windows build, and live integration tests.*
