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

1. **Bring up the repo on GitHub.**
   - Create `curantes/wolfi-images`, push, create the GitHub App (`vars.BOT_APP_ID`, `secrets.BOT_APP_PRIVATE_KEY`).
   - Ruleset on `main`: PRs only, no force-push or deletion, required `Build Result`.
   - First manual `build.yml` run; set GHCR package visibility; check `cosign verify` and `gh attestation verify` from outside CI.
2. **Remaining images**: `static`, `glibc-dynamic`, go, nodejs, openjdk, php, rust, etcd, valkey, curl, git, rabbitmq, coredns, haproxy, nginx. Check each product's endoflife.date slug against its Wolfi package naming; add a variant (e.g. `-jre`, `-fpm`) only where the runtime really differs.
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

- **apko embeds the git commit** (`org.opencontainers.image.revision`) unless built with `--vcs=false`, so every commit changed every digest.
- **The Kyverno CLI skips `imageRegistry` context lookups unless run with `--registry`**, and a rule `message` can't use `foreach` variables.
- **Free Chainguard images only publish `latest`/`latest-dev`**, so version streams mean building with apko.
- **apko's tarball output is docker-loadable** and its `index.json` *is* the image index. Writing to a directory path fails ("is a directory"), so convert the tarball (`scripts/oci_layout.py`) to push by digest with `regctl`.
- **Wolfi uses a merged `/usr`**: `/bin` and `/sbin` are symlinks to `/usr/bin`.
- **endoflife.date's `isEol` is computed for today.** Classify from `eolFrom` so the result is deterministic.
- **Distroless Python has no `ensurepip` wheels**: `venv` works only without pip; pip lives in `-dev`.
