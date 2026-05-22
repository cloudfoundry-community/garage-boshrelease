# Changelog

All notable changes to garage-boshrelease are documented here.

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
