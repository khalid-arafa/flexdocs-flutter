# Changelog

## 0.2.0 - 2026-08-11

Additive throughout — no API is removed or changed shape, so upgrading from
0.1.0 requires no code changes.

### Added

- **`AuthService.refreshToken()`** exchanges the current token for a fresh one,
  returning `null` when it is no longer valid (expired, or revoked from another
  device) — the cue to send the user back to a login screen. The server
  re-verifies signature, project binding and the revocation counter before
  issuing a replacement, so a token already invalidated cannot be laundered
  through it. There is no background refresh timer by design: the SDK stores no
  tokens and so has nothing to refresh on your behalf. Call it from your
  `getToken` callback, or on app resume.
- **`AuthService.revokeTokens()`** is "log out everywhere". It invalidates every
  token issued to the account, deliberately including the one making the call,
  so discard the token your app holds immediately afterwards. Backed by a
  counter on the account rather than a session store, so individual sessions
  cannot be revoked separately. Both endpoints existed on the backend and the
  SDK simply had no knowledge of them; the 0.1.0 note claiming the backend
  exposes no logout route is superseded by this.
- **Typed exceptions.** `FlexDocsException` and subtypes — `Auth`, `Permission`,
  `NotFound`, `Validation`, `RateLimit`, `Server`, `Network`, `Upload` — each
  carrying `message`, the server's stable `code`, and `status`. Previously a
  failure surfaced as an `ArgumentError`, a bare `Exception(String)`, or a
  non-throwing `ApiResponse`, none of which let a caller tell "wrong password"
  from "server unreachable" without matching on message text.
- **`ApiResponse.code`** reads the stable identifier the API now returns on every
  error body, and **`ApiResponse.orThrow()`** converts a response into the
  matching typed exception. Calls still return an `ApiResponse`, so checking
  `ok` remains valid; `orThrow()` is the opt-in for try/catch, and the only way
  to distinguish a legitimately empty read from a denied one.
- **`SocketServiceOptions.uploadWindow`** (default 8) caps how many upload chunks
  may be in flight at once. Lower it to bound memory, raise it for
  high-latency links; 1 is strict lockstep.

### Fixed

- **A watch registered before the socket existed was lost permanently.**
  `connect()` awaits your `getToken` callback *before* assigning the socket, so
  this window is wider than "before you call connect()". Both halves failed
  silently: the subscribe was never sent, and its listener was never attached
  either — so such a watch received no events, ever. Pending listeners are now
  buffered and attached when the socket arrives, and the first connect replays
  any subscribe that had nowhere to go. Re-sending one the server already has is
  harmless: its registry is keyed by collection plus filter and drops duplicates.
- **Uploads had no flow control.** Every chunk was pushed into the send queue in
  one synchronous burst, buffering the whole file a second time and giving the
  server no way to slow a client down; a disconnect mid-file was ignored after
  the first chunk. Chunks are now gated on the server's per-chunk
  acknowledgement, and `upload:done` waits until every chunk is acknowledged
  rather than merely sent.
- **Upload progress ran backwards.** The per-chunk ack is `{name, received:
  true}` and carries no byte count, but the handler read an `uploaded` field
  from it — so every ack reset progress to 0. Progress is now derived from the
  chunks this client has had acknowledged.

## 0.1.0 - 2026-07-30

This package is consumed as a git dependency by ref, so moving a ref forward
across this release will not warn you. Read the breaking section first.

### Breaking

- **`AuthService.logout()` removed.** The backend exposes no logout route and
  its JWTs are stateless, so the call could only ever fail. Ending a session
  means discarding the token your app holds — the one it returns from
  `ApiClientOptions.getToken`.
- **`AuthService.registerWithEmail()` no longer accepts `roles`.**
  Self-registration is anonymous and the server ignores a client-supplied
  `roles` field, so passing it only ever looked like it worked. Assign roles
  from an admin-authenticated context.
- **Auth routes corrected.** Every route `AuthService` called was admin-only and
  returned 403, which made the class unusable against this backend:

  | was | now |
  | --- | --- |
  | `/auth/login` | `/auth/login-with-email` |
  | `/auth/register` | `/auth/register-with-email` |
  | `/auth/token-login` | `/auth/login-with-token` |
  | `/auth/reset-password` | `/auth/send-reset-password-email` |
  | `/auth/me` | `/auth/current-user` |

  If you were bypassing `AuthService` and driving `ApiClient` directly, that
  workaround is no longer necessary.

### Fixed

- **Watch subscriptions are replayed after every reconnect.** Server
  subscriptions are per-connection: a reconnect arrives with a new socket id
  belonging to no rooms, and the server cannot restore them. Every `watch()`
  therefore went permanently silent after the first network blip — a closed
  laptop lid, a tunnel, a wifi switch — with no error surfaced.
- **The replay is ordered before your `onConnect` callback.** It previously ran
  in a microtask while `onConnect` ran synchronously, so an app that re-created
  its watches in that callback — exactly the workaround written for the missing
  replay — drained the registry before the replay read it, leaving the replay a
  no-op.
- **The user token is re-sent before the replayed subscriptions.** The server
  checks read rules against `socket.sender`, which only exists once the token
  lands, so a subscribe that overtook it was silently denied.
- **`StreamController`s are closed by `SocketService.close()`.** Watch streams
  previously hung with no done event, so a `StreamBuilder` never learned the
  socket had died.
- **Cancelling a watch during its initial fetch now tears down correctly.**
  `onCancel` was assigned inside the initial `get()` callback, so a cancel
  during that window left the subscription to be created afterwards and never
  released — the case an app hits on every resume.
- **`AuthUser.fromJson` accepts `uid`**, which is what this backend returns for
  the user id. It previously looked only for `_id`/`id` and so could not parse
  its own server's auth response.

### Notes

- `watch()` deliberately remains a single-subscription stream. Making it
  broadcast was tried and reverted: a broadcast controller drops the initial
  snapshot for any listener attaching after the async fetch resolves, and turns
  cancel-then-relisten into a permanent silent hang rather than a `StateError`.
  Serving several listeners from one `watch()` needs the last snapshot cached
  and replayed on listen — a feature, not a lifecycle fix.
- Adds `test/socket_reconnect_test.dart`, the first coverage of the reconnect
  path. `socket_service_test.dart` built a service with no socket at all, so
  none of this behaviour was previously exercised.

## 0.0.1

* Initial release.
