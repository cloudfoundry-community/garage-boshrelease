# garage-boshrelease

A BOSH release that packages [Garage](https://garagehq.deuxfleurs.fr/) — a
lightweight, S3-compatible distributed object storage system — as a
BPM-managed service for Cloud Foundry and BOSH-based platforms.

## Overview

Garage is a self-hosted, distributed object store built in Rust. It exposes an
S3-compatible API on port 3900, an admin API on port 3903 (loopback), and an
RPC inter-node channel on port 3901. This release:

- Ships the statically-linked `x86_64-unknown-linux-musl` binary as a BOSH
  blob — no compilation needed on the stemcell.
- Manages the process under BPM with correct persistent disk, ephemeral
  volume, and ulimit settings.
- Uses a `garage-rpc` BOSH link so all instances enumerate peer IPs at
  render time — no hard-coded peer list.
- Bootstraps cluster layout idempotently on instance index 0 via the
  post-deploy hook (opt-out via `garage.layout.manual: true`).
- Delivers `rpc_secret` and `admin_token` via on-disk files, not inline in
  the TOML config, to avoid secrets appearing in rendered templates.

## Requirements

| Dependency | Version | Notes |
|---|---|---|
| BOSH CLI | v7+ | Required for blob management and release creation |
| BPM | any | Colocated job from the `bpm` BOSH release |
| Stemcell | ubuntu-noble | Any recent Ubuntu Noble stemcell |
| Persistent disk | 10 GiB+ (production: 100 GiB+) | One disk per instance; `meta/` should be SSD-backed |
| Garage binary | v1.3.1 | Fetched by `scripts/fetch blobs` (or `make download-blobs`) |

No runtime library dependencies: Garage's musl binary is fully statically
linked and has no glibc or OpenSSL requirements on the stemcell.

## Quickstart

**1. Fetch the blob:**

```bash
./scripts/fetch blobs           # or: make download-blobs
```

**2. Create a dev release:**

```bash
bosh create-release --force
bosh -e <your-director> upload-release
```

**3. Deploy (single-node example):**

```yaml
instance_groups:
- name: garage
  jobs:
  - name: garage
    release: garage
    provides:
      garage-rpc: { as: garage-rpc }
    consumes:
      garage-rpc: { from: garage-rpc }
    properties:
      garage:
        rpc_secret: "<64-char-hex-from-openssl-rand-hex-32>"
        admin_token: "<strong-random-token>"
        replication_factor: 1
  - name: bpm
    release: bpm
  instances: 1
  persistent_disk_type: default
  ...
```

**4. Run smoke tests:**

```bash
bosh -d <deployment> run-errand smoke-tests
```

## Properties

| Property | Default | Description |
|---|---|---|
| `garage.rpc_port` | `3901` | RPC inter-node port, exported via `garage-rpc` link |
| `garage.s3_port` | `3900` | S3 API bind port |
| `garage.admin_port` | `3903` | Admin API port (loopback only) |
| `garage.s3_region` | `"garage"` | S3 region label in API responses |
| `garage.s3_root_domain` | `""` | Optional vhost-style bucket domain suffix |
| `garage.replication_factor` | `1` | Replication factor (1 = dev, 3 = production) |
| `garage.db_engine` | `"lmdb"` | DB engine: `lmdb` (production) or `sqlite` (dev/test) |
| `garage.metadata_dir` | `/var/vcap/store/garage/meta` | LMDB metadata path — use SSD |
| `garage.data_dir` | `/var/vcap/store/garage/data` | Object block path — HDD-OK |
| `garage.block_size` | `1048576` | Data block size in bytes (1 MiB) |
| `garage.compression_level` | `1` | Zstd compression level (-99 to 22) |
| `garage.metadata_fsync` | `false` | Extra LMDB corruption protection (costs performance) |
| `garage.consistency_mode` | `"consistent"` | `consistent`, `degraded`, or `dangerous` |
| `garage.log_level` | `"info"` | `trace`, `debug`, `info`, `warn`, or `error` |
| `garage.rpc_secret` | *(required)* | 64-char hex cluster secret — identical on all nodes |
| `garage.admin_token` | *(required)* | Admin API bearer token |
| `garage.layout.manual` | `false` | If true, skip auto-bootstrap in post-deploy |
| `garage.layout.capacity` | `"1T"` | Capacity passed to `garage layout assign -c` |
| `garage.bpm.open_files` | `65536` | BPM open_files ulimit |
| `smoke_tests.timeout_secs` | `30` | `curl --max-time` for smoke test requests |

See `jobs/garage/spec` for complete property declarations with types and
descriptions. Properties in the `smoke-tests` job mirror the main job.

## Cluster Bootstrap

On the first deploy, the post-deploy hook on instance index 0:

1. Runs `garage status` to detect nodes showing `NO ROLE ASSIGNED`.
2. For each unassigned node: calls `garage layout assign <prefix> -z <az> -c <capacity>`.
3. Reads the current layout version from `garage layout show`.
4. Calls `garage layout apply --version <current+1>`.

This is idempotent: subsequent deploys find no unassigned nodes and exit
immediately. Set `garage.layout.manual: true` on any instance group to skip
auto-bootstrap entirely and manage the cluster layout yourself.

For production clusters (`replication_factor: 3`), each node must be in a
distinct BOSH availability zone so Garage places replicas in different zones.
The post-deploy hook reads `spec.az` for the zone label.

## Architecture

```mermaid
graph TD
    subgraph "BOSH VM (each instance)"
        BPM["BPM process manager"]
        BIN["/var/vcap/packages/garage/bin/garage"]
        CFG["/var/vcap/jobs/garage/config/garage.toml"]
        S3["S3 API :3900"]
        ADMIN["Admin API :3903 (loopback)"]
        RPC["RPC :3901"]
        DISK[("Persistent Disk\n/var/vcap/store/garage\n  meta/  ← LMDB\n  data/  ← blocks")]
    end

    BPM --> BIN
    BIN --> CFG
    BIN --> S3
    BIN --> ADMIN
    BIN --> RPC
    BIN --> DISK

    RPC <-->|"garage-rpc BOSH link\npeer discovery"| RPC
```

## Smoke Tests

The `smoke-tests` BOSH errand performs a full S3 round-trip against the
cluster. It requires the `garage-rpc` BOSH link and an S3 access key + secret
key (sourced from Vault; see the kit MANUAL for setup). Run it with:

```bash
bosh -d <deployment> run-errand smoke-tests
```

The errand:

1. Probes `GET http://<peer>:3903/health` on every peer — fails if any peer
   returns non-200.
2. Creates a uniquely named bucket (`smoke-<timestamp>-<pid>`).
3. Uploads a small test object via PutObject.
4. Downloads and verifies the object content via GetObject.
5. Deletes the object and bucket.
6. Confirms the object is gone via HeadObject (expects HTTP 404).

Auth uses AWS Signature Version 4 via `curl` and `openssl`. No packages
beyond the Ubuntu Noble stemcell base tools are needed.

## Release Process

Final releases are created by the `.github/workflows/release.yml` workflow
on tag push. The workflow:

1. Installs the latest BOSH CLI.
2. Downloads the Garage binary from the upstream CDN.
3. Verifies the SHA256 digest.
4. Runs `bosh add-blob` and `bosh upload-blobs`.
5. Runs `bosh create-release --final --version <tag>`.
6. Publishes the `.tgz` and its SHA256 checksum to GitHub Releases.

To trigger a release: push a `v`-prefixed tag (e.g., `git tag v0.2.0 && git push --tags`).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow, blob
management instructions, and PR guidelines.

## License

Apache License 2.0. See [LICENSE](LICENSE).

Copyright 2026 Cloud Foundry Community.
