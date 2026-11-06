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
- Shiori Share previously sent `X-Session-Id`, which is why v1.8.0 "broke"
  (issue #1176 was closed as a client auth problem, not a server bug).
- So: ship the Bearer version of Shiori Share first (works on both), then
  upgrade the server.
- Shiori runs DB migrations on startup. v1.7.4 -> v1.8.0 should be treated
  as one-way: rollback = old image **and** restore the volume backup.

## Status

- [x] `Dockerfile.fly`: `FROM alpine:3.19` -> `FROM alpine:3.24` (deployed)
- [x] Phase 1 done; Phase 2 ready to deploy (2026-11-05)
- [x] Test volume restored from prod snapshot `vs_PgRy0QjwLXb7sG3Pm3ppAB9`
- [x] Deploy 1 (Alpine 3.24 + v1.7.4) in prod, 2026-11-06
- [x] Test upgraded to Shiori v1.8.0 on Alpine 3.24.4, 2026-11-06 04:26 UTC
      (release v3; HTTP 200, DB integrity ok, 1526 bookmarks / 394 tags / 3 accounts)
- [x] Prod upgraded to Shiori v1.8.0, 2026-11-06 05:12 UTC (release v13).
      Fresh volume snapshot confirmed before deployment; no data downloaded.

## Phase 0: Prep

- [x] Snapshot prod volume: `vs_PgRy0QjwLXb7sG3Pm3ppAB9`, 2026-11-05 23:30 UTC
      on `vol_4y8pmp30n1n6pz9r` (5-day retention, expires ~2026-11-10): `fly volumes list -a shiori-emberson`, then
      `fly volumes snapshots create <vol-id>`
- [ ] Also take a file-level backup (portable, restorable into another app).
      Full portable tarball/download skipped for this rollout per Hugh's
      instruction to use snapshots. Before Deploy 2, saved a consistent DB
      copy at `/mnt/shiori/pre-v1.8.0-shiori.db` on prod; integrity check ok.
      NOTE: the data is ~3.8 GB. `/tmp` is on the small root fs, bzip2 is very
      slow, and prod auto-suspends during long SSH sessions (only HTTP
      traffic keeps it up). Keep it awake (e.g. `curl` it every 20s), write the
      tarball to the volume (~6 GB free), skip compression, and run tar under
      `nohup`. Delete the tarball from the volume after downloading it.
      Once prod runs an image with `sqlite3` (added 2026-11-06), use
      `sqlite3 shiori.db ".backup /mnt/shiori/shiori-backup.db"` for a consistent
      DB copy while Shiori is running, and tar that instead of the live db/wal.
      Original commands:
      ```sh
      fly ssh console -a shiori-emberson -C "tar cjf /tmp/shiori-backup.tbz -C /mnt/shiori ."
      fly ssh sftp get -a shiori-emberson /tmp/shiori-backup.tbz ./shiori-backup-$(date +%F).tbz
      ```
- [x] Check whether `SHIORI_HTTP_SECRET_KEY` is set (`fly secrets list`).
      Confirmed deployed on prod before v1.8.0 rollout, 2026-11-06.
      Checked 2026-11-05: NOT set on prod; set (staged) on test. Setting it on
      prod restarts prod, so do it with the prod rollout.
      If unset, Shiori generates a random JWT key at startup, so every
      restart/redeploy invalidates all tokens. The app copes (401 -> re-login),
      but set it as a secret on both test and prod:
      `fly secrets set SHIORI_HTTP_SECRET_KEY=$(openssl rand -hex 32)`
      (name verified: same in v1.7.4 and v1.8.0 `internal/config/config.go`)
- [x] Skim v1.8.0 release notes / config docs for renamed env vars
      (`SHIORI_DIR` etc.) and breaking changes. No renames. New, off by default:
      `SHIORI_HTTP_SERVE_WEB_UI_V2`, `SHIORI_SSO_PROXY_AUTH_*` (leave SSO off:
      its default trusted ranges include `fc00::/7`, which covers Fly's 6PN).
      Auth change (#1069) is the X-Session-Id removal above.

## Phase 1: Parameterise the build

- [x] Make the Shiori version a build arg so test and prod differ only by toml:
      ```dockerfile
      ARG SHIORI_VERSION=v1.7.4
      FROM ghcr.io/go-shiori/shiori:${SHIORI_VERSION} AS shiori-source
      ```
- [x] Update the v1.8.0 downgrade comment in `Dockerfile.fly` (the reason no longer holds)

## Phase 2: Test environment

- [x] Create `fly.test.toml`: copy of `fly.toml` with
      `app = 'shiori-emberson-test'`, mount source `shiori_emberson_test_data`,
      and `[build.args] SHIORI_VERSION = "v1.7.4"` to start
- [x] `fly apps create shiori-emberson-test`
- [x] `fly volume create shiori_emberson_test_data -a shiori-emberson-test -r dfw -n 1 -s 10 --snapshot-id vs_PgRy0QjwLXb7sG3Pm3ppAB9`
      (seeded from the prod snapshot, so the tarball restore step below isn't needed)
- [x] Set the same secrets on the test app (Phase 0): `SHIORI_HTTP_SECRET_KEY` staged
- [x] `fly deploy -c fly.test.toml` (2026-11-06; restored data checked:
      fsck clean, `PRAGMA integrity_check` ok, 1524 bookmarks / 393 tags / 3 accounts)
- [x] ~~Restore prod data into test~~ (not needed; volume was seeded from the snapshot):
      ```sh
      fly ssh sftp shell -a shiori-emberson-test   # put shiori-backup-*.tbz /tmp/
      fly ssh console -a shiori-emberson-test -C "tar xjf /tmp/shiori-backup-<date>.tbz -C /mnt/shiori"
      fly machine restart -a shiori-emberson-test
      ```
- [x] Optional: keep test private (no cert/CNAME; just use `shiori-emberson-test.fly.dev`)

## Phase 3: Test Alpine 3.24 with Shiori v1.7.4 (one change at a time)

- [x] `fly ssh console -a shiori-emberson-test -C "cat /etc/alpine-release"` -> 3.24.4
- [x] Web UI: log in, list, search, open an archived page, add/edit/delete a bookmark
- [x] `shiori-cli --server https://shiori-emberson-test.fly.dev --user <me> probe`
      (from `../shiori_share`, `make cli`): expect `session-id` and `bearer` both accepted
- [x] Current Shiori Share build (X-Session-Id) against test (macOS + iOS): save a bookmark, tags load
- [ ] Bearer build of Shiori Share against test: same checks (see shiori_share TODO)
- [x] `fly logs -a shiori-emberson-test`: no errors

## Phase 4: Test Shiori v1.8.0

- [x] Set `SHIORI_VERSION = "v1.8.0"` in `fly.test.toml`; retained the existing
      test dataset. Pre-upgrade test-volume snapshot
      `vs_KlZ7ey66Gmo4fZXRvwvkB` confirmed created (4.0 GiB, 5-day retention).
      Also saved a consistent DB copy on the test volume at
      `/mnt/shiori/pre-v1.8.0-shiori.db`; integrity check ok.
- [x] `fly deploy -c fly.test.toml`; release v3 complete, 2026-11-06 04:26 UTC.
      Logs show `Starting Shiori v1.8.0` and HTTP server startup, with no
      migration errors. Verified `shiori version` = 1.8.0, Alpine = 3.24.4,
      homepage HTTP 200, `PRAGMA integrity_check` ok; counts unchanged:
      1526 bookmarks / 394 tags / 3 accounts.
- [x] Web UI working on test v1.8.0 (confirmed by Hugh, 2026-11-06).
- [x] Shiori Share extension works against test v1.8.0 (confirmed by Hugh,
      2026-11-06; production rollout requested).
- [ ] `shiori-cli ... probe`: expect `bearer` accepted, `session-id` rejected
- [ ] `shiori-cli ... add https://example.com --tags cli-test` creates a bookmark
- [ ] Bearer build of Shiori Share: save bookmark, fetch tags, tag a bookmark, 401 -> re-login path
- [ ] Old (X-Session-Id) build of Shiori Share fails, confirming the app must ship first
- [ ] Restart the machine; confirm the app recovers (token still valid if secret key set)
- [ ] Rollback rehearsal: deploy v1.7.4 back + restore backup; confirm it comes up clean

## Phase 5: Prod rollout

- [ ] Shiori Share Bearer build installed on all devices (iPhone, Mac) and
      confirmed working against prod v1.7.4
- [x] Fresh prod snapshot `vs_qZPe4kyY2NxgtYkoG23QY7n` confirmed created
      before Deploy 2 (5-day retention); consistent DB copy saved on volume
      at `/mnt/shiori/pre-v1.8.0-shiori.db`. No data downloaded, per Hugh.
- [x] Deploy 1: Alpine 3.24, Shiori v1.7.4 -> verify (`/etc/alpine-release`, UI, app)
      Done 2026-11-06 04:10 UTC, after snapshot `vs_GqLDGMmw3Qz1SklnmoAxoQ2`. Also
      added sqlite and set `SHIORI_HTTP_SECRET_KEY` on prod. Verified: 3.24.4,
      HTTP 200 on both hostnames, `PRAGMA quick_check` ok, 1524 bookmarks.
- [x] Deploy 2: `SHIORI_VERSION` default -> `v1.8.0`, release v13,
      2026-11-06 05:12 UTC. Deployed image digest matches tested image:
      `sha256:57b718af0fe1f79222720cc888cb173a7cec3e263285c8fb3ffced7aefc0c352`.
      Verified version 1.8.0 / Alpine 3.24.4; both hostnames HTTP 200;
      `PRAGMA integrity_check` ok; counts unchanged at 1524 bookmarks /
      393 tags / 3 accounts. Shiori startup logs show no migration errors.
- [x] iOS Shiori Share saves against prod v1.8.0 after clearing the cached
      token (confirmed by Hugh, 2026-11-06).
      iOS save failed with 502 after rollout (2026-11-06 05:17–05:18 UTC).
      Server logs show invalid JWT signature, then legacy-handler panic
      `session has been expired`. Client cache is not scoped to server and
      is not cleared when server URL changes; Test Connection does not
      replace it. Suspect cached test token sent to prod. Clearing Password
      in Shiori Share settings cleared the token; fresh prod login fixed saves.
- [ ] Scope Shiori Share token cache to server/user and invalidate it on
      configuration changes.
- [ ] Confirm authenticated web UI against prod v1.8.0;
      `shiori-cli ... probe` against prod remains unrun.
- [ ] Rollback plan if deploy 2 fails: redeploy v1.7.4 and restore the backup
      taken just before deploy 2

## Phase 6: Cleanup

- [ ] `fly apps destroy shiori-emberson-test` (removes its volume too)
- [ ] Delete local backup tarballs once prod has been stable for a while
- [x] `sqlite` added to the image (for integrity checks / `.backup`)
- [ ] Optional: pin images by digest; optionally replace the copied CA bundle
      with `apk add ca-certificates tzdata`
