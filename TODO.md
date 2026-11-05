# TODO: Upgrade to Alpine 3.24 + Shiori v1.8.0

Goal: move prod (`shiori-emberson`) from `alpine:3.19` + Shiori `v1.7.4` to
`alpine:3.24` + Shiori `v1.8.0`, proving it on a throwaway test app first.

Companion plan: `../shiori_share/TODO.md` (the app must switch to
`Authorization: Bearer` before prod moves to v1.8.0).

## Why the order matters

- Shiori v1.7.4's legacy API (`/api/bookmarks`, `/api/tags`) checks
  `Authorization: Bearer <token>` first, then falls back to `X-Session-Id`.
- Shiori v1.8.0 dropped `X-Session-Id` entirely: only `Authorization`
  (or the `token` cookie) is accepted.
- Shiori Share currently sends `X-Session-Id`, which is why v1.8.0 "broke"
  (issue #1176 was closed as a client auth problem, not a server bug).
- So: ship the Bearer version of Shiori Share first (works on both), then
  upgrade the server.
- Shiori runs DB migrations on startup. v1.7.4 -> v1.8.0 should be treated
  as one-way: rollback = old image **and** restore the volume backup.

## Status

- [x] `Dockerfile.fly`: `FROM alpine:3.19` -> `FROM alpine:3.24` (edited, not deployed)
- [ ] Everything below

## Phase 0: Prep

- [ ] Snapshot prod volume: `fly volumes list -a shiori-emberson`, then
      `fly volumes snapshots create <vol-id>`
- [ ] Also take a file-level backup (portable, restorable into another app):
      ```sh
      fly ssh console -a shiori-emberson -C "tar cjf /tmp/shiori-backup.tbz -C /mnt/shiori ."
      fly ssh sftp get -a shiori-emberson /tmp/shiori-backup.tbz ./shiori-backup-$(date +%F).tbz
      ```
- [ ] Check whether `SHIORI_HTTP_SECRET_KEY` is set (`fly secrets list`).
      If unset, Shiori generates a random JWT key at startup, so every
      restart/redeploy invalidates all tokens. The app copes (401 -> re-login),
      but set it as a secret on both test and prod:
      `fly secrets set SHIORI_HTTP_SECRET_KEY=$(openssl rand -hex 32)`
      (verify the variable name against the v1.8.0 docs first)
- [ ] Skim v1.8.0 release notes / config docs for renamed env vars
      (`SHIORI_DIR` etc.) and breaking changes

## Phase 1: Parameterise the build

- [ ] Make the Shiori version a build arg so test and prod differ only by toml:
      ```dockerfile
      ARG SHIORI_VERSION=v1.7.4
      FROM ghcr.io/go-shiori/shiori:${SHIORI_VERSION} AS shiori-source
      ```
- [ ] Update the v1.8.0 downgrade comment in `Dockerfile.fly` (the reason no longer holds)

## Phase 2: Test environment

- [ ] Create `fly.test.toml`: copy of `fly.toml` with
      `app = 'shiori-emberson-test'`, mount source `shiori_emberson_test_data`,
      and `[build.args] SHIORI_VERSION = "v1.7.4"` to start
- [ ] `fly apps create shiori-emberson-test`
- [ ] `fly volume create shiori_emberson_test_data -a shiori-emberson-test -r dfw -n 1`
- [ ] Set the same secrets on the test app (Phase 0)
- [ ] `fly deploy -c fly.test.toml`
- [ ] Restore prod data into test:
      ```sh
      fly ssh sftp shell -a shiori-emberson-test   # put shiori-backup-*.tbz /tmp/
      fly ssh console -a shiori-emberson-test -C "tar xjf /tmp/shiori-backup-<date>.tbz -C /mnt/shiori"
      fly machine restart -a shiori-emberson-test
      ```
- [ ] Optional: keep test private (no cert/CNAME; just use `shiori-emberson-test.fly.dev`)

## Phase 3: Test Alpine 3.24 with Shiori v1.7.4 (one change at a time)

- [ ] `fly ssh console -a shiori-emberson-test -C "cat /etc/alpine-release"` -> 3.24.x
- [ ] Web UI: log in, list, search, open an archived page, add/edit/delete a bookmark
- [ ] `shiori-cli --server https://shiori-emberson-test.fly.dev --user <me> probe`
      (from `../shiori_share`, `make cli`): expect `session-id` and `bearer` both accepted
- [ ] Current Shiori Share build (X-Session-Id) against test: save a bookmark, tags load
- [ ] Bearer build of Shiori Share against test: same checks (see shiori_share TODO)
- [ ] `fly logs -a shiori-emberson-test`: no errors

## Phase 4: Test Shiori v1.8.0

- [ ] Re-take the backup into test if prod has changed; `SHIORI_VERSION = "v1.8.0"` in `fly.test.toml`
- [ ] `fly deploy -c fly.test.toml`; watch `fly logs` for migration output
- [ ] Web UI checks as in Phase 3 (bookmarks, tags, archives, thumbnails all present)
- [ ] `shiori-cli ... probe`: expect `bearer` accepted, `session-id` rejected
- [ ] `shiori-cli ... add https://example.com --tags cli-test` creates a bookmark
- [ ] Bearer build of Shiori Share: save bookmark, fetch tags, tag a bookmark, 401 -> re-login path
- [ ] Old (X-Session-Id) build of Shiori Share fails, confirming the app must ship first
- [ ] Restart the machine; confirm the app recovers (token still valid if secret key set)
- [ ] Rollback rehearsal: deploy v1.7.4 back + restore backup; confirm it comes up clean

## Phase 5: Prod rollout

- [ ] Shiori Share Bearer build installed on all devices (iPhone, Mac) and
      confirmed working against prod v1.7.4
- [ ] Fresh prod snapshot + file backup (Phase 0 commands)
- [ ] Deploy 1: Alpine 3.24, Shiori v1.7.4 -> verify (`/etc/alpine-release`, UI, app)
- [ ] Deploy 2: `SHIORI_VERSION` default -> `v1.8.0` -> verify UI, app, logs,
      and `shiori-cli ... probe` against prod
- [ ] Rollback plan if deploy 2 fails: redeploy v1.7.4 and restore the backup
      taken just before deploy 2

## Phase 6: Cleanup

- [ ] `fly apps destroy shiori-emberson-test` (removes its volume too)
- [ ] Delete local backup tarballs once prod has been stable for a while
- [ ] Optional: pin images by digest; optionally replace the copied CA bundle
      with `apk add ca-certificates tzdata`
