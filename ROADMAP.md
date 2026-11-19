# Roadmap

Working notes. Update as items land.

## Status (2026-11-19)

- On GitHub and in CI: daily stream updates, lock refreshes (automerged) and full rebuilds; signing, attestations and publishing to GHCR work. Ruleset on `main`: PRs only, no force-push or deletion, required `Build Result`.
- Images: `static`, `glibc-dynamic`, `python` 3.11–3.15; with this PR go, nodejs, openjdk, php and rust.
- Streams must be maintained by public Wolfi, not just packaged (see Lessons Learned). nodejs 22 is left out for that reason.

## Scope

Language runtimes and small base images only. Services and tools (etcd, valkey, rabbitmq, coredns, haproxy, nginx, curl, git) come from their upstream images or Docker Hardened Images; public Wolfi stopped maintaining several of them. Alternatives considered for the gaps, and why not:

- **Alpine with apko**: same tooling and scannable, but one version per release (no parallel python/go/rust streams) and musl (no `glibc-dynamic`).
- **Nix** (`dockerTools`/`nix2container`): many parallel versions on glibc, but Grype and Trivy cannot scan `/nix/store`, so the fixable-CVE gate would go, and FHS-expecting wheels and binaries break.
- **Debian, AlmaLinux 10, Fedora, openSUSE Tumbleweed**: glibc and good scanner data (except Fedora), but no apko: the build, lock and SBOM pipeline would have to be rebuilt around dnf/zypper/mmdebstrap, and only Tumbleweed and Fedora ship many parallel versions.

## Next

1. **Finish bring-up**: set GHCR package visibility; check `cosign verify` and `gh attestation verify` from outside CI.
2. **Kyverno policy in a cluster.** `policy/verify-wolfi-images.yaml` passes `policy/test.sh` (Kyverno CLI 1.19.2, live registry and Rekor). Still to do: run it in kind, add rules for the upstream service images (signature checks where they are signed, e.g. Docker Hardened Images; an explicit allowlist otherwise), and decide whether to migrate to `ImageValidatingPolicy`/`ValidatingPolicy` (CEL), since Kyverno 1.19 deprecates `ClusterPolicy`.
3. **harden-runner block mode.** All jobs run `egress-policy: audit`. Collect the endpoints from a few runs, then switch to `block` with per-job allowlists.
4. **Lock refresh for PR branches.** `refresh-locks.yml` always opens an automerging PR against `main`; dispatched on another branch it should commit the locks to that branch instead, so stale PRs can be refreshed in CI with the pinned apko.
5. **Comparison table** with hummingbird-mirror (CVE counts, size, stream coverage) in both READMEs.
6. **Generator tests in CI.** `tests/generator/` has the first unit tests (`python3 -m unittest discover tests/generator`); add offline fixtures (`--offline`) and run them in CI.

## Deferred (post-v1)

- Own packages with melange (e.g. legacy Java)
- FIPS variants
- Internal Quay as the target registry
- OpenSCAP scans

## Lessons Learned

- **Public Wolfi only maintains the newest stream of many products.** Older streams (nodejs-22, etcd-3.6, haproxy-3.2/3.3, nginx-stable, valkey-9.0, ...) stopped getting builds months ago while Wolfi's security database kept recording fixes for versions that were never published. The generator now requires a stream to be maintained (no unpublished fix, newest build at most 90 days old). The age limit applies only to per-version packages: rolling ones like glibc can go months without a rebuild while being fully patched, and the first version of the check would have frozen `glibc-dynamic`.
- **Signing and attesting depend on Rekor**, which has transient outages: a single 500 failed the publish of three streams. `cosign` calls retry with backoff, and the attestation actions get a second attempt.
- **apko embeds the git commit** (`org.opencontainers.image.revision`) unless built with `--vcs=false`, so every commit changed every digest.
- **apko's release binaries are only verifiable through a Rekor log search** (`.sig`/`.crt`, no bundle), so verifying them made every build fail while Rekor's v1 search API returned 500s. Run apko from its container image pinned by digest instead.
- **The Kyverno CLI skips `imageRegistry` context lookups unless run with `--registry`**, and a rule `message` can't use `foreach` variables.
- **Free Chainguard images only publish `latest`/`latest-dev`**, so version streams mean building with apko.
- **apko's tarball output is docker-loadable** and its `index.json` *is* the image index. Writing to a directory path fails ("is a directory"), so convert the tarball (`scripts/oci_layout.py`) to push by digest with `regctl`.
- **Wolfi uses a merged `/usr`**: `/bin` and `/sbin` are symlinks to `/usr/bin`.
- **endoflife.date's `isEol` is computed for today.** Classify from `eolFrom` so the result is deterministic.
- **Distroless Python has no `ensurepip` wheels**: `venv` works only without pip; pip lives in `-dev`.
