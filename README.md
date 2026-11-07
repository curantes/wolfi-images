# Wolfi Images

[![Build](https://github.com/curantes/wolfi-images/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/curantes/wolfi-images/actions/workflows/build.yml?query=branch%3Amain)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/curantes/wolfi-images/badge)](https://scorecard.dev/viewer/?uri=github.com/curantes/wolfi-images)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)

Minimal, hardened container images built from [Wolfi](https://github.com/wolfi-dev) packages with [apko](https://github.com/chainguard-dev/apko), for every version stream that [endoflife.date](https://endoflife.date) lists as supported.

**This project is built from Wolfi packages and is not affiliated with or endorsed by Chainguard, Inc.** The checks described below are our own.

Work in progress is in [ROADMAP.md](ROADMAP.md).

## Available Images

All images are multi-arch (`linux/amd64`, `linux/arm64`) under `ghcr.io/curantes/wolfi-images/`, run as `65532:65532` with working directory `/home/nonroot`, and contain no setuid binaries.

| Image | Streams | `<stream>` | `<stream>-dev` |
|---|---|---|---|
| `static` | `latest` | CA certificates, tzdata, `/etc/passwd`; no libc, no shell. For static binaries (Go with `CGO_ENABLED=0`) | – |
| `glibc-dynamic` | `latest` | `static` plus glibc, libgcc and libstdc++. For dynamically linked binaries (cgo, Rust, C/C++) | adds bash, busybox and `apk` |
| `go` | `1.26`, `1.27` | – (run on `static` or `glibc-dynamic`) | Go toolchain, gcc, git, ssh client, bash, `apk`; `GOTOOLCHAIN=local` |
| `nodejs` | `22`, `24`, `26` | Node.js; distroless, no npm | adds npm, `build-base`, bash, busybox and `apk` |
| `openjdk` | `8`, `11`, `17`, `21`, `25`, `27` | JRE; distroless | full JDK plus bash, busybox and `apk` |
| `php` | `8.2`–`8.5` | PHP CLI with common extensions; distroless. Also `<stream>-fpm`: PHP-FPM on port 9000, distroless | adds Composer, git, bash, busybox and `apk` |
| `python` | `3.11`–`3.15` | CPython; distroless (no shell, no `apk`, no pip) | adds pip, Python headers, `build-base`, bash, busybox and `apk` |
| `rust` | `1.99` | – (run on `glibc-dynamic` or `static`) | rustc, cargo, clippy, rustfmt, gcc, git, bash, `apk` |
| `coredns` | `1.14` | CoreDNS; without a Corefile answers `whoami` on port 53 (needs unprivileged low ports: Docker's default, Podman `--sysctl net.ipv4.ip_unprivileged_port_start=0`); distroless | adds bash, busybox and `apk` |
| `curl` | `8.23` | curl with HTTP/2 and the CA bundle; entrypoint `curl`; distroless | adds bash, busybox and `apk` |
| `etcd` | `3.6` | etcd, etcdctl, etcdutl; client 2379, peer 2380, data in `/var/lib/etcd`; distroless | adds bash, busybox and `apk` |
| `git` | `2.56` | git with HTTPS and SSH remotes (ssh client); entrypoint `git`; distroless | adds bash, busybox and `apk` |
| `haproxy` | `3.2`, `3.3`, `3.4` | HAProxy; no configuration, mount one at `/usr/local/etc/haproxy/haproxy.cfg`; distroless | adds bash, busybox and `apk` |
| `nginx` | `1.30` (stable), `1.31` (mainline) | nginx serving a default page on 8080, configuration in `/etc/nginx/conf.d/`, logs to stdout/stderr; distroless | adds bash, busybox and `apk` |
| `rabbitmq` | `4.3` | RabbitMQ broker and CLI; AMQP on 5672, data in `/var/lib/rabbitmq` (keep the hostname stable); **ships busybox sh**, since the server and CLI are shell scripts | adds bash and `apk` |
| `valkey` | `8.1`, `9.0`, `9.1` | Valkey server and CLI on 6379, data in `/data`; protected mode refuses remote clients until a password is set; distroless | adds bash, busybox and `apk` |

`openjdk` is Wolfi's OpenJDK build, following [Eclipse Temurin's support dates](https://endoflife.date/eclipse-temurin) (endoflife.date has no product for plain OpenJDK); it is not Temurin. PHP extensions: bcmath, ctype, curl, dom, fileinfo, iconv, intl, mbstring, mysqlnd, opcache, openssl, PDO (MySQL, PostgreSQL, SQLite), posix, simplexml, sodium, xml, xmlreader, xmlwriter and zip.

Supported versions Wolfi doesn't package (currently etcd 3.5/3.7, haproxy 2.6/2.8/3.0, rabbitmq 4.4 and valkey 7.2/8.0) are tracked in the `stream-missing` issue. Data directories are owned by `65532` with GID 0 and group write (except etcd's, which etcd requires to be `0700`), so they also work with an arbitrary UID.

The current streams and their status are in [`generated/catalog.json`](generated/catalog.json).

## Streams and End of Life

- A stream exists while endoflife.date lists its cycle as supported **and** Wolfi packages it on both architectures.
- After its EOL date a stream is **deprecated** for 30 days: it is still rebuilt, and its images carry `io.github.curantes.wolfi-images.status: deprecated`.
- Then it is **frozen**: it is no longer rebuilt and its tags stay where they are. Migrate before then.
- Supported cycles that Wolfi doesn't package are listed in the `stream-missing` issue.
- Images whose product isn't on endoflife.date follow Wolfi: `static` and `glibc-dynamic` have one rolling `latest` stream; others build Wolfi's newest minor version, and the previous minor's tags freeze when it moves on.

## Tags

- `<stream>[-dev]` (e.g. `3.12`, `3.12-dev`): moves to each new approved build.
- `<version>[-dev]` (e.g. `3.12.16`): the upstream version. It moves when the same version is rebuilt with updated dependencies.
- `<version>[-dev]-<UTC timestamp>` (e.g. `3.12.16-20261107T050312Z`): unique per approval and never overwritten.

There is no `latest`. **Pin by digest** (`image@sha256:…`) in production.

```dockerfile
FROM ghcr.io/curantes/wolfi-images/python:3.13-dev AS build
WORKDIR /app
RUN python -m venv /app/venv
COPY requirements.txt .
RUN /app/venv/bin/pip install --no-cache-dir -r requirements.txt
COPY . .

FROM ghcr.io/curantes/wolfi-images/python:3.13
WORKDIR /app
COPY --from=build /app /app
ENV PATH=/app/venv/bin:$PATH
ENTRYPOINT ["python", "-m", "myapp"]
```

## How Images Are Built

Inputs are the only hand-edited files: [`images/base.yaml`](images/base.yaml) (shared apko template) and `images/<name>/image.yaml` (endoflife.date product, Wolfi package pattern, variants). Everything in `generated/` is produced from them:

1. [`update-streams.yml`](.github/workflows/update-streams.yml) runs daily [`scripts/generate.py`](scripts/generate.py): endoflife.date ∩ Wolfi → `generated/catalog.json` and one apko config per stream and variant. Stream changes arrive as a PR for review.
2. [`refresh-locks.yml`](.github/workflows/refresh-locks.yml) runs daily [`scripts/lock.sh`](scripts/lock.sh): `apko lock` pins every package (version and checksum) and the Wolfi signing key. Changes arrive as a PR that automerges once the build passes.
3. [`build.yml`](.github/workflows/build.yml) runs [`build-image.yml`](.github/workflows/build-image.yml) for each changed stream:
   1. **Build** with apko from the lock. Only `packages.wolfi.dev/os` is allowed, verified with the pinned key in [`keys/`](keys/). Builds are reproducible: the same lock gives the same digest. apko itself is verified against its release signature before use.
   2. **Test and scan** natively on amd64 and arm64: `tests/<name>/test.sh` (including user 65532, an arbitrary UID, no setuid files, and the variant contract), a Syft check that the Wolfi distro and its APKs are detected, a Grype gate that **fails on fixable HIGH/CRITICAL vulnerabilities** (accepted findings in `vex/` as OpenVEX), and a non-blocking Trivy cross-check.
   3. **Publish** (on `main` only): push **by digest** with no tag, sign keylessly with cosign, attest SLSA build provenance, the apko SPDX SBOMs (index and per platform), and a verification summary (VSA). **Only then move the tags.**

A digest that fails is never tagged. A daily full run rebuilds every stream (same digest), rescans it against current vulnerability data, and finishes any promotion that didn't complete. Failures open a `wolfi-alert` issue.

## Verifying Images

```bash
IMAGE=ghcr.io/curantes/wolfi-images/python:3.13
WF=https://github.com/curantes/wolfi-images/.github/workflows/build-image.yml@refs/heads/main

# Signature
cosign verify "$IMAGE" \
  --certificate-identity "$WF" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

# SLSA provenance and our approval (VSA)
for type in https://slsa.dev/provenance/v1 https://slsa.dev/verification_summary/v1; do
  gh attestation verify "oci://$IMAGE" --bundle-from-oci \
    --repo curantes/wolfi-images \
    --signer-workflow curantes/wolfi-images/.github/workflows/build-image.yml \
    --predicate-type "$type"
done

# SBOM
cosign verify-attestation --type spdxjson "$IMAGE" \
  --certificate-identity "$WF" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Development

```bash
python3 scripts/generate.py           # regenerate the catalog and apko configs
scripts/lock.sh                       # lock every config (needs apko)
apko build --lockfile generated/python/3.13.lock.json \
  generated/python/3.13.apko.yaml local/python:3.13 /tmp/python.tar
docker load -i /tmp/python.tar
tests/python/test.sh local/python:3.13-amd64 3.13
```

Adding an image: write `images/<name>/image.yaml` and `tests/<name>/test.sh`, then run the two scripts.

## Setup

The bot workflows need a GitHub App with contents and pull-requests write access, installed on this repository: `vars.BOT_APP_ID` and `secrets.BOT_APP_PRIVATE_KEY`. Pull requests created with `GITHUB_TOKEN` would not run the required checks.

## Trademarks

Wolfi and Chainguard are trademarks of Chainguard, Inc. They are used here only to identify the upstream packages and tools. The images contain open source packages under their own licenses (see each image's SBOM). This repository's Apache-2.0 license covers only its own code and configuration.
