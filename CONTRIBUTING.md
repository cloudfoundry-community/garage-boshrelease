# Contributing to garage-boshrelease

This document covers the development workflow, blob management, and release
process for garage-boshrelease.

## Prerequisites

- [BOSH CLI](https://bosh.io/docs/cli-v2/) v7 or later
- [uv](https://docs.astral.sh/uv/) (runs `scripts/fetch` as a self-contained Python script)
- A BOSH director for integration testing (optional for unit specs)
- Ruby 3.1+ if running template rendering specs via `rspec`

## Blob Management

Blobs are not stored in git. Use `scripts/fetch blobs` to download the
Garage binary and register it with the BOSH CLI:

```bash
# Fetch default version (v2.3.0) for x86_64
./scripts/fetch blobs

# Fetch a specific version
./scripts/fetch blobs --version 1.3.2

# Fetch both x86_64 and aarch64
./scripts/fetch blobs --all-arches

# Fetch only the aarch64 build
./scripts/fetch blobs --arch aarch64
```

Or via `make`:

```bash
make download-blobs                  # x86_64 only
make download-blobs VERSION=1.3.2    # different version
make download-blobs-all              # both arches
```

The script downloads the binary from `https://garagehq.deuxfleurs.fr/_releases/`,
computes the SHA256 digest with Python's stdlib `hashlib`, and runs
`bosh add-blob`. It prints the full `blobs.yml` entry on success so you
can verify the sha field.

To upload blobs to the S3 blobstore (requires `config/private.yml`):

```bash
cp config/private.yml.example config/private.yml
# Edit config/private.yml with valid S3 credentials
bosh upload-blobs
```

`config/private.yml` is git-ignored and must never be committed.

## Dev Release

```bash
bosh create-release --force
bosh -e <your-director> upload-release
```

## Running Unit Specs

Template rendering specs live in `spec/jobs/`. Run them with:

```bash
bundle exec rspec spec/
```

Specs use `bosh-template` to render ERb templates without a running director.
Add specs when adding or modifying job templates.

## Final Release

Final releases are created by CI on tag push. To create one locally:

```bash
# Populate config/private.yml with S3 credentials first
bosh create-release --final --version X.Y.Z
git add releases/ config/blobs.yml
git commit -m "Release X.Y.Z"
git tag vX.Y.Z
git push --tags
```

## PR Guidelines

- Keep each PR focused on a single logical concern.
- Include or update `spec/` tests for any job template changes.
- Update `CHANGELOG.md` with a summary of changes under the relevant version.
- Do not commit `config/private.yml`, `blobs/`, `.dev_builds/`, or
  `.final_builds/`.
- Run `python3 -c "import ast; ast.parse(open('scripts/fetch').read())"` before submitting `scripts/fetch` changes.
