# garage-boshrelease — development targets.
#
# Usage:
#   make download-blobs              # fetch x86_64 Garage v2.3.0 into blobs/
#   make download-blobs VERSION=1.3.2   # fetch a different version
#   make download-blobs-all          # fetch both x86_64 and aarch64
#   make dev-release                 # bosh create-release --force
#   make final-release VERSION=0.1.0 # bosh create-release --final --version=...
#   make clean                       # remove .dev_builds, dev_releases, tmp
#   make help                        # show this list

VERSION ?= 2.3.0

.DEFAULT_GOAL := help

.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) \
	 | awk 'BEGIN {FS = ":.*?##"} {printf "  %-22s %s\n", $$1, $$2}' \
	 || true
	@echo ""
	@echo "Variables:"
	@echo "  VERSION   Garage release version without leading 'v' (default: $(VERSION))"

.PHONY: download-blobs
download-blobs: ## Fetch the x86_64 Garage binary from upstream and add to blobs/
	./scripts/fetch blobs --version $(VERSION)

.PHONY: download-blobs-all
download-blobs-all: ## Fetch both x86_64 and aarch64 Garage binaries
	./scripts/fetch blobs --version $(VERSION) --all-arches

.PHONY: dev-release
dev-release: ## Build a development release (bosh create-release --force)
	bosh create-release --force

.PHONY: final-release
final-release: ## Build a final release (requires VERSION=x.y.z)
	@if [ "$(VERSION)" = "2.3.0" ]; then \
	  echo "Set VERSION to the release version, e.g. make final-release VERSION=0.1.0" >&2; \
	  exit 1; \
	fi
	bosh create-release --final --version=$(VERSION)

.PHONY: clean
clean: ## Remove dev build artifacts (keeps blobs/)
	rm -rf .dev_builds dev_releases /tmp/garage-*-v*.bin

.PHONY: clean-blobs
clean-blobs: ## Remove the local blob cache (forces re-download on next build)
	rm -rf blobs/
