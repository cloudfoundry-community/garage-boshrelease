# Changelog

All notable changes to garage-boshrelease are documented here.

## Unreleased

### Changed

- Upgrade packaged Garage binary to v2.3.0 (`x86_64-unknown-linux-musl`).
- `jobs/smoke-tests`: Phase 2 now operates within the auto-provisioned default
  bucket (`garage.default_bucket`). `CreateBucket` and `DeleteBucket` calls are
  removed; the bucket is created automatically by Garage on first start via
  `GARAGE_DEFAULT_BUCKET`. The test key is unique per run
  (`smoke-<epoch>-<pid>`).

### Added

- `jobs/garage` bpm: `GARAGE_DEFAULT_ACCESS_KEY`, `GARAGE_DEFAULT_SECRET_KEY`,
  and `GARAGE_DEFAULT_BUCKET` env vars wired from job properties so Garage
  auto-provisions the root S3 key and default bucket on first start.
- `jobs/garage` bpm: `--single-node` server flag emitted automatically when the
  `garage-rpc` link has exactly one instance, enabling single-node layout
  auto-assignment. `--default-bucket` is always emitted to trigger bucket
  auto-creation.
- `jobs/garage` properties: `garage.access_key` (no default),
  `garage.secret_key` (no default), `garage.default_bucket` (default `garage`).
- `jobs/smoke-tests` properties: `garage.default_bucket` (default `garage`).
- `scripts/fetch`: default version bumped to `2.3.0`.

### Fixed

- `jobs/garage` bpm: removed the explicit `/var/vcap/data/garage` volume. BPM
  already provides the per-job data directory; declaring it again is rejected
  with "cannot conflict with default job data or store directories".
- `jobs/garage` `garage.toml`: removed the empty `[admin] trace_sink = ""`.
  Garage treats an empty string as a misconfigured OpenTelemetry exporter and
  aborts during tracing init, crashing the process on every start.
- `jobs/garage` pre-start: the `rpc_secret` and `admin_token` files are now
  written `0600` and owned by `vcap`. Garage v2.x refuses to start when these
  files are group- or world-readable.
- `jobs/garage` drain: all diagnostics are written to stderr. BOSH parses drain
  stdout as the seconds-remaining integer, so non-numeric stdout failed drain.
- `jobs/garage` post-deploy: dropped `GARAGE_RPC_HOST=127.0.0.1:<port>`. Garage
  v2.x requires that variable be a full `<node-id>@<ip>:<port>` identifier; a
  bare host:port is rejected, breaking the layout bootstrap. The CLI now
  connects to the local node via `rpc_bind_addr` from the config file.
- `jobs/smoke-tests`: HeadObject now uses `curl --head` instead of
  `curl -X HEAD`, which would block until timeout waiting for a response body
  that a HEAD response never sends.

## 0.0.1 (2026-05-21)

Initial release of the BOSH release. Packages Garage v1.3.1
(`x86_64-unknown-linux-musl`) and runs it under `bpm`.

### Added

- `packages/garage` — statically-linked upstream binary copied to
  `$BOSH_INSTALL_TARGET/bin/garage`; no compilation needed.

- `jobs/garage` — main job; `bpm.yml.erb` configures the Garage process;
  `garage.toml.erb` enumerates RPC peers from the `garage-rpc` BOSH link;
  `monit` delegates lifecycle to `bpm`.

- `jobs/garage/templates/bin/{pre-start,post-start,post-deploy}.erb`
  — pre-start creates `meta/` and `data/` subdirectories on the persistent
  disk and writes secret files; post-start polls the admin health endpoint
  until the node is ready; post-deploy idempotently bootstraps cluster layout
  on instance index 0.

- `jobs/smoke-tests` — BOSH errand. Probes `GET /health` on every peer from
  the `garage-rpc` link, then runs a full S3 cycle (CreateBucket, PutObject,
  GetObject with content verification, DeleteObject, HeadObject expecting 404,
  DeleteBucket) against the primary peer using `curl` and `openssl` (AWS
  SigV4). No extra packages needed.

- `.github/workflows/release.yml` — tag-triggered final-release workflow with
  SHA256 verification and GitHub Release publication.

- `scripts/fetch` — uv-runnable Python script (Python 3.11+, stdlib only).
  Subcommand `blobs` downloads Garage binaries from the upstream CDN,
  computes SHA256, and registers them with `bosh add-blob`. Supports
  `--version`, `--arch`, and `--all-arches`.

- `Makefile` with targets `download-blobs`, `download-blobs-all`,
  `dev-release`, `final-release`, `clean`, `clean-blobs`, and `help`.

### Properties (highlights)

- `garage.rpc_secret`, `garage.admin_token` — required, no defaults; delivered
  via files written by pre-start, not inline in TOML.
- `garage.rpc_port` (default 3901), `garage.s3_port` (default 3900),
  `garage.admin_port` (default 3903)
- `garage.replication_factor` (default 1), `garage.db_engine` (default `lmdb`)
- `garage.metadata_dir` (default `/var/vcap/store/garage/meta`),
  `garage.data_dir` (default `/var/vcap/store/garage/data`)
- `garage.layout.manual` (default false) — set true to skip auto-bootstrap
- `garage.layout.capacity` (default `1T`) — capacity string for layout assign
- `garage.peer.tls.{ca,certificate,key}` — optional RPC peer TLS
- `garage.bpm.open_files` (default 65536)
- `smoke_tests.timeout_secs` (default 30)
