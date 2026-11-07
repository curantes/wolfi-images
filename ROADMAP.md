# Roadmap

Working notes. Update as items land.

## Status (2026-11-07)

- First vertical slice: `python` 3.11–3.15, each as `<stream>` and `<stream>-dev`.
- Verified locally (not yet in CI):
  - `scripts/generate.py` against live endoflife.date and Wolfi data, including the deprecated → frozen transitions with `--today`
  - `apko lock` for all 10 configs; versions 3.11.18 – 3.15.2
  - two `apko build`s of `python:3.12` are bit-identical, and the index digest computed by `scripts/oci_layout.py` matches apko's SBOM
  - image filesystem (amd64): no `/bin/sh`, no `apk`, no setuid files, `nonroot` 65532; `-dev` has sh, apk, pip and gcc
  - Grype detects distro `wolfi` and its APKs; no fixable HIGH/CRITICAL findings
- Not verified yet: container tests (no container runtime in the authoring sandbox), every workflow, publishing to GHCR.

## Next

1. **Repo on GitHub is live** (2026-11-07): ruleset on `main`, bot GitHub App, Renovate, public GHCR packages. Still to do: run `cosign verify` and `gh attestation verify` from outside CI, and watch the first automerged lock refresh PR.
2. **All 18 images are defined** (72 builds). Their container tests first run in CI on the image PRs (#5-#7). Watch the first runs of the service images (rabbitmq startup, nginx and php-fpm as an arbitrary UID). A full daily run is now 72 builds; if it gets slow, rescan published digests instead of rebuilding unchanged locks.
3. **Kyverno policy in a cluster.** `policy/verify-wolfi-images.yaml` passes `policy/test.sh` (Kyverno CLI 1.19.2, live registry and Rekor). Still to do: run it in kind, and decide whether to migrate to `ImageValidatingPolicy`/`ValidatingPolicy` (CEL), since Kyverno 1.19 deprecates `ClusterPolicy`.
4. **harden-runner block mode.** All jobs run `egress-policy: audit`. Collect the endpoints from a few runs, then switch to `block` with per-job allowlists.
5. **Comparison table** with hummingbird-mirror (CVE counts, size, stream coverage) in both READMEs.
6. **Generator tests** with offline fixtures (`--offline`), run in CI.

## Deferred (post-v1)

- Own packages with melange (e.g. legacy Java)
- FIPS variants
- Internal Quay as the target registry
- OpenSCAP scans

## Lessons Learned

- **apko's release binaries are only verifiable through a Rekor log search** (`.sig`/`.crt`, no bundle), so verifying them made every build fail while Rekor's v1 search API returned 500s. Run apko from its container image pinned by digest instead.
- **The Kyverno CLI skips `imageRegistry` context lookups unless run with `--registry`**, and a rule `message` can't use `foreach` variables.
- **Free Chainguard images only publish `latest`/`latest-dev`**, so version streams mean building with apko.
- **apko's tarball output is docker-loadable** and its `index.json` *is* the image index. Writing to a directory path fails ("is a directory"), so convert the tarball (`scripts/oci_layout.py`) to push by digest with `regctl`.
- **Wolfi uses a merged `/usr`**: `/bin` and `/sbin` are symlinks to `/usr/bin`.
- **endoflife.date's `isEol` is computed for today.** Classify from `eolFrom` so the result is deterministic.
- **Distroless Python has no `ensurepip` wheels**: `venv` works only without pip; pip lives in `-dev`.
