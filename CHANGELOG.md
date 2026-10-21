# Changelog

All notable changes to garage-boshrelease are documented here.

## 0.2.1 (2026-10-21)

### Changed

- `jobs/garage` drain: when BOSH deletes one instance, drain now takes its node out of the cluster itself. It checks that the layout is stable, that nothing is staged, that no node with a role is down, and that the remaining nodes still cover the replication factor. Then it stages `garage layout remove` for its own node, checks that its removal is the only staged change, applies the next layout version, and waits until the layout is stable and the node's data directory holds no blocks. Any refusal before the apply drops the staged removal. Before, drain refused to delete a node that held a role, and once the role was gone it waited only for a stable layout, which Garage reaches before the blocks have left the node.
- `jobs/garage` drain: a node whose role is already gone waits for its data to move, for up to `garage.drain.delete_wait_secs`, and a deploy that runs out of time leaves the node running without a role, so the next deploy picks up the wait. When blocks are still left fifteen minutes after the layout settled and nothing is queued, drain queues them once with `garage repair --yes blocks`.
- `jobs/garage` drain: deleting the whole deployment no longer needs `bosh delete-deployment --force`, because drain lets BOSH go ahead when pre-stop reports that the deployment is being deleted.
- `jobs/garage` bpm: Garage starts through `bin/garage-server`, which passes `--single-node --default-bucket` only when the `garage-rpc` link has one instance and the node has no stored layout yet. A cluster scaled down to one instance used to restart in single-node mode, which Garage refuses once the layout is past its first version, so the last node never came back.
- `jobs/garage` post-deploy: when a single node grows into a cluster, the role that single-node mode made (zone `dc1`, tag `default`, and the disk size as its capacity) moves to the zone of the node's BOSH AZ with `garage.layout.capacity`, in the same layout version that adds the new nodes. Garage used to give that node no partitions, so it held no data once the cluster rebalanced.
- `jobs/garage` post-deploy: a single instance now provisions the root key and the default bucket on every deploy, like a cluster does, and warns about any role in the layout that isn't its own node's.

### Added

- `jobs/garage` pre-stop: records the next state of the VM, the instance, and the deployment that BOSH passes to pre-stop, for drain to read.
- `jobs/garage` properties: `garage.drain.delete_wait_secs` (default `3600`).

## 0.2.0 (2026-10-21)

### Changed

- Upgrade packaged Garage binary to v2.3.0 (`x86_64-unknown-linux-musl`).
- `jobs/smoke-tests`: Phase 2 now operates within the auto-provisioned default
  bucket (`garage.default_bucket`). `CreateBucket` and `DeleteBucket` calls are
  removed; the bucket is created automatically by Garage on first start via
  `GARAGE_DEFAULT_BUCKET`. The test key is unique per run
  (`smoke-<epoch>-<pid>`).
- `jobs/garage` post-deploy: the instance with the highest index in the `garage-rpc` link now makes the layout changes, and post-start joins every node through the instance with the lowest index. Both were chosen by position in the link before, which broke when the indexes had gaps.
- `jobs/garage` post-deploy: it waits until every instance in the link is a healthy Garage node and fails if one is still missing after a minute. Before, it counted failed nodes as present and carried on with a warning. Each instance's node id now comes from that instance's own admin API (`GetNodeInfo`) rather than from matching addresses in `garage status`, which can list a node that has just gone away as healthy for close to a minute. The check runs again just before the plan is made, and after the apply the hook confirms that every instance's node holds a role.
- `jobs/garage` post-deploy: it waits until the local node has the newest layout any peer reports. A single node that already had its own layout was scaled out onto a stale view of version 0, and the apply was rejected.
- `jobs/garage` post-deploy: it refuses to run when the layout has staged changes it didn't make, because `garage layout apply` would commit them unreviewed, and the message names `garage layout revert --yes`. It never changes the role of a node outside the link.
- `jobs/garage` post-deploy: the whole layout change is planned before anything is staged, and when the hook fails or is interrupted with changes staged, it drops them with `garage layout revert --yes`. Before, a failure between the first assign and the apply left half a change staged, and every later deploy refused to run.
- `jobs/garage` post-deploy: an instance whose address doesn't resolve stops the hook before it changes anything. Before, the instance only got a warning and no role, and the rest of the plan went ahead without it.
- `jobs/garage` post-deploy: every `garage` CLI call is limited to 30 seconds and every admin API request to at most 10 seconds, so a node that stops answering fails the deploy instead of hanging it.
- `jobs/garage` post-deploy: each new role carries the tags `bosh-id-<instance id>` and `<instance group>/<index>`. When the hook tags or replaces an existing role, it keeps the role's other tags.
- `jobs/garage` post-deploy: the root key, the default bucket, and the key's grant are each checked before they're written, so an already provisioned cluster sees no writes, and a step that fails while a layout change settles is retried for at least three minutes and at most about four. A step is written only when its check shows that it's missing, and a check that gets no answer, for example without a quorum, is retried rather than treated as missing. When Garage rejects the root key itself, the deploy fails at once with Garage's reason, and the secret stays out of the output. Before, the grant ran on every deploy and failed the deploy when the cluster had no quorum.
- `jobs/garage` post-deploy: with `garage.layout.manual: true`, the root key and the default bucket are created on the first deploy after the operator applies a layout, and until then the hook logs that it's waiting.
- `jobs/garage` drain: drain no longer stops the process, which raced monit, and it no longer always reports success. On an ordinary stop it waits up to two minutes for the block resync queue to empty. When BOSH is deleting the instance, it refuses while the node still holds a role in a layout with more than one node, and it waits up to 30 minutes for the layout to become stable once the role is gone. The README describes the scale-down procedure that drain points to.
- `jobs/garage` post-start: when a node that has a layout can't reach its peers, a 503 from `/health` is accepted with a warning after 45 seconds, so a fully stopped cluster can start one instance at a time. A node that can reach all its peers and still answers 503 fails after two minutes.
- `jobs/garage` post-start: the join target now tries to connect to every other instance, so a join target that comes back with a wiped disk finds the cluster again.
- `jobs/garage`: the admin token reaches curl through a root-only header file (`curl -H @file`), and the root S3 secret is imported through the admin API (`POST /v2/ImportKey`) from a root-only file that pre-start writes. Neither secret appears on a command line or in a rendered script any more.
- `jobs/smoke-tests`: the AWS Signature Version 4 HMACs are computed in bash over `openssl dgst -sha256`, so no key reaches a command line. The secret key comes from a rendered file that the errand restricts to root, and the response body goes to a `mktemp` file that's removed on exit.

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
- `scripts/fetch`: the default version is now `2.3.0`.
- `jobs/garage` properties: `garage.admin_bind_address` (default empty). An
  empty value binds the admin API to loopback for one node and to the
  instance IP for a cluster. Off loopback, `/metrics` requires the admin
  token (`metrics_require_token`).
- `jobs/garage` post-deploy: in a cluster, the root S3 key is imported, the
  default bucket is created, and the key is granted read, write, and owner
  access, all idempotently.
- `jobs/garage` pre-start: a new guard protects the replication factor. Pre-start records `garage.replication_factor` in `/var/vcap/store/garage/replication_factor` and refuses to start a node whose rendered value differs, with a message that explains how to keep or replace the cluster. bpm runs the same check before every start. A node from an older release gets the marker from post-start once Garage has started with the configured value.
- `jobs/garage` post-deploy: a node that comes back with a new node id after its disk was lost takes over its old role through `garage layout assign --replace`, but only when exactly one role that no link instance's node holds carries the instance's `bosh-id` tag. When the hook can't prove which role was the node's own, because more than one role carries the tag, the tagged node is still up somewhere else, or an untagged role's node is down, it stops with nothing changed and prints the exact `garage layout assign ... --replace` commands to run by hand. A node outside the link, a node that is down for a moment, and a node added by hand are never replaced. Once the replaced nodes are down, the hook runs `garage layout skip-dead-nodes`, but only when they are the only down nodes in the live layout versions, because that command marks every down node as caught up. Otherwise it prints the command and the reason, and the deploy still succeeds.
- `jobs/garage` post-deploy: a single-instance deployment is left to Garage's `--single-node` mode, which refuses to start once the layout version is above 1.
- `jobs/garage` post-deploy: roles made by an earlier release get their `bosh-id` and instance tags on the first deploy, staged and applied together with any other assignment, with their zone, capacity, and other tags unchanged. A role is tagged only when the node that an instance's admin API names holds it.
- README: we now document the scale-down procedure, the replication factor guard, how to start a stopped cluster, secret handling, and the upgrade from 0.0.1. Garage v1 and v2 nodes can't share a cluster, so the upgrade stops every node and starts them all on v2 together with `bosh deploy --canaries=0 --max-in-flight=100%`, after a table repair and a metadata snapshot.

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
- `jobs/garage` bpm: a cluster no longer fails to start. `--default-bucket`
  and the `GARAGE_DEFAULT_*` variables are emitted only with `--single-node`,
  because Garage v2.x refuses `--default-bucket` in any other mode.
- `jobs/garage` post-start: a new cluster node whose layout version is still
  0 may answer 503 on `/health`, and post-start now accepts that. Before,
  the first deploy of every cluster failed at post-start, because the layout
  is applied only later, in post-deploy.
- `jobs/garage` post-start: joining nodes read the join target's node id from its admin API (`GetNodeInfo`). Garage v2.x ignores a bare `GARAGE_RPC_HOST=<ip>:<port>`, so the old lookup returned the joining node's own id and no node ever joined. A new node that can't join now fails post-start instead of logging a warning.
- `jobs/garage` post-deploy: each node is assigned the zone of its own BOSH
  AZ. Before, every node got the zone of the instance running the hook.
- `jobs/garage` post-deploy: the layout version is read from Garage v2.x's
  `Current cluster layout version: N` line. The old `^Version:` match never
  hit, so every layout change after the first tried to apply version 1.
- `jobs/garage` env.sh: no longer exports a bare `GARAGE_RPC_HOST`, and it
  exports `GARAGE_RPC_SECRET` from the staged file.
- `jobs/smoke-tests`: HeadObject now uses `curl --head` instead of
  `curl -X HEAD`, which would block until timeout waiting for a response body
  that a HEAD response never sends.
- `jobs/garage` post-start and post-deploy: a failed `garage layout show` is now fatal. Before, a CLI error read as layout version 0, which made a node look brand new.
- `jobs/garage` post-deploy: link addresses are resolved with `getent ahostsv4`, and an instance without a BOSH AZ gets a loud warning instead of a silent fallback.
- `jobs/garage`: IPv6 addresses are bracketed in `garage.toml` and in the scripts, and a wildcard admin bind of `::` is reached through `::1`.

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
