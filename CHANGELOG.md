# Changelog

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
