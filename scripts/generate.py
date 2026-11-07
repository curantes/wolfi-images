#!/usr/bin/env python3
"""Generate the stream catalog and apko configs.

For every images/<name>/image.yaml:

1. Take the release cycles of its endoflife.date product.
2. Keep the cycles that Wolfi packages on every architecture (all variant
   packages must resolve by name; apko resolves their dependencies).
3. Classify each cycle:
   - supported:  not EOL                        -> built
   - deprecated: EOL for less than GRACE_DAYS   -> built, annotated
   - frozen:     EOL for GRACE_DAYS or more     -> no longer built; tags stay
   - missing:    supported but not in Wolfi     -> reported, not built
4. Write generated/catalog.json and generated/<name>/<tag>.apko.yaml, and
   remove configs and locks of streams that are no longer built.

Products without endoflife.date data have one rolling stream (see
rolling_releases); `newest-only: true` builds only the newest cycle Wolfi
provides (see wolfi_streams).

Locks are written separately by scripts/lock.sh (needs apko).

Usage: generate.py [--today YYYY-MM-DD] [--offline DIR]
  --offline DIR reads DIR/endoflife/<product>.json and DIR/<arch>/APKINDEX
  instead of the network (for tests).
"""

from __future__ import annotations

import argparse
import copy
import datetime as dt
import io
import json
import re
import sys
import tarfile
import urllib.request
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
IMAGES = ROOT / "images"
OUT = ROOT / "generated"
GRACE_DAYS = 30
WOLFI = "https://packages.wolfi.dev/os"
ARCHS = ["x86_64", "aarch64"]
EOL_API = "https://endoflife.date/api/v1/products/{}"
USER_AGENT = "wolfi-images-generator (+https://github.com/curantes/wolfi-images)"
ANNOTATION_PREFIX = "io.github.curantes.wolfi-images"


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    last: Exception | None = None
    for _ in range(3):
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return resp.read()
        except OSError as exc:  # URLError, timeouts, resets
            last = exc
    raise RuntimeError(f"fetching {url} failed: {last}")


def parse_apkindex(text: str) -> dict[str, list[str]]:
    """Package name -> versions."""
    pkgs: dict[str, list[str]] = {}
    name = None
    for line in text.splitlines():
        if line.startswith("P:"):
            name = line[2:]
        elif line.startswith("V:") and name:
            pkgs.setdefault(name, []).append(line[2:])
        elif not line:
            name = None
    return pkgs


def load_indexes(offline: Path | None) -> dict[str, dict[str, list[str]]]:
    indexes = {}
    for arch in ARCHS:
        if offline:
            text = (offline / arch / "APKINDEX").read_text()
        else:
            raw = fetch(f"{WOLFI}/{arch}/APKINDEX.tar.gz")
            with tarfile.open(fileobj=io.BytesIO(raw), mode="r:gz") as tar:
                member = tar.extractfile("APKINDEX")
                if member is None:
                    raise RuntimeError(f"no APKINDEX in {arch} index")
                text = member.read().decode()
        indexes[arch] = parse_apkindex(text)
    return indexes


def load_releases(product: str, offline: Path | None) -> list[dict]:
    if offline:
        data = json.loads((offline / "endoflife" / f"{product}.json").read_text())
    else:
        data = json.loads(fetch(EOL_API.format(product)))
    return data["result"]["releases"]


def version_key(version: str) -> list[int]:
    return [int(n) for n in re.findall(r"\d+", version.split("-r")[0].split("_")[0])]


def subst(value, stream: str, package: str | None = None):
    if isinstance(value, str):
        value = value.replace("{stream}", stream)
        return value.replace("{package}", package) if package else value
    if isinstance(value, list):
        return [subst(v, stream, package) for v in value]
    if isinstance(value, dict):
        return {k: subst(v, stream, package) for k, v in value.items()}
    return value


def in_wolfi(indexes, names: list[str]) -> list[str]:
    """Packages missing on any architecture."""
    return sorted({f"{n} ({arch})" for arch, idx in indexes.items() for n in names if n not in idx})


def upstream_version(version: str) -> str:
    """3.12.16_git20261030-r0 -> 3.12.16"""
    return version.rsplit("-r", 1)[0].split("_")[0]


def newest(indexes, package: str) -> str | None:
    """Newest upstream version of a package if it is the same on every architecture."""
    found = {upstream_version(max(idx[package], key=version_key)) for idx in indexes.values() if package in idx}
    if len(found) != 1 or any(package not in idx for idx in indexes.values()):
        return None
    return found.pop()


def in_cycle(version: str, cycle: str) -> bool:
    return version == cycle or version.startswith(cycle + ".")


def templates(spec: dict) -> list[str]:
    pkg = spec.get("package")
    return [] if pkg is None else [pkg] if isinstance(pkg, str) else list(pkg)


def rolling_releases(spec: dict, indexes) -> list[dict]:
    """Streams for products without endoflife.date data: one current stream.

    - `stream: latest` (fixed name, e.g. static)
    - `package: coredns-{stream}`: the newest stream Wolfi packages
    - `package: curl`: major.minor of the newest Wolfi version
    """
    if "stream" in spec:
        return [{"name": str(spec["stream"]), "isEol": False}]
    cycles = set()
    for tpl in templates(spec):
        if "{stream}" in tpl:
            rx = re.compile(re.escape(tpl).replace(re.escape("{stream}"), r"([0-9][0-9.]*)") + "$")
            names = set.intersection(*(set(idx) for idx in indexes.values()))
            cycles |= {m.group(1) for n in names if (m := rx.match(n))}
        elif version := newest(indexes, tpl):
            cycles.add(".".join(version.split(".")[:2]))
    if not cycles:
        raise RuntimeError(f"no Wolfi package for {templates(spec)}")
    return [{"name": max(cycles, key=version_key), "isEol": False}]


def wolfi_streams(spec: dict, releases: list[dict], indexes) -> dict[str, tuple[str | None, list[str]]]:
    """cycle -> (package providing it, packages missing from Wolfi; empty = available).

    A `{stream}` template names one package per cycle (python-{stream}). A plain
    package name is a rolling package that provides the cycle matching its
    newest version (git; nginx-stable and nginx-mainline). Variant packages may
    use {package} for whichever package provides the cycle.
    """
    result: dict[str, tuple[str | None, list[str]]] = {}
    for rel in releases:
        stream = rel["name"]
        provider, why = None, []
        for tpl in templates(spec):
            if "{stream}" in tpl:
                candidate = tpl.replace("{stream}", stream)
                if not in_wolfi(indexes, [candidate]):
                    provider = candidate
                    break
                why.append(f"no {candidate}")
            elif "stream" in spec:  # fixed stream name (latest): no version to match
                if not in_wolfi(indexes, [tpl]):
                    provider = tpl
                    break
                why.append(f"no {tpl}")
            else:
                version = newest(indexes, tpl)
                if version and in_cycle(version, stream):
                    provider = tpl
                    break
                why.append(f"{tpl} is {version or 'missing'}")
        if templates(spec) and provider is None:
            result[stream] = (None, why)
            continue
        needed = sorted({p for v in spec["variants"].values() for p in subst(v["packages"], stream, provider)})
        result[stream] = (provider, in_wolfi(indexes, needed))
    if spec.get("newest-only"):
        # Only the newest cycle Wolfi provides is built; older cycles are
        # neither built nor reported, newer ones are reported as missing.
        ok = [s for s, (_, why) in result.items() if not why]
        if ok:
            top = max(ok, key=version_key)
            result = {s: v for s, v in result.items() if version_key(s) >= version_key(top)}
    return result


def classify(rel: dict, today: dt.date) -> tuple[str, str | None]:
    # Decide from eolFrom rather than isEol, which endoflife.date computes for
    # its own clock; this keeps --today meaningful and the run deterministic.
    eol = rel.get("eolFrom")
    is_eol = today >= dt.date.fromisoformat(eol) if eol else bool(rel.get("isEol"))
    if not is_eol:
        return "supported", eol
    if eol and today < dt.date.fromisoformat(eol) + dt.timedelta(days=GRACE_DAYS):
        return "deprecated", eol
    return "frozen", eol


def merge(base: dict, extra: dict) -> dict:
    out = copy.deepcopy(base)
    for key, value in extra.items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = merge(out[key], value)
        elif isinstance(value, list) and isinstance(out.get(key), list):
            out[key] = out[key] + [v for v in value if v not in out[key]]
        else:
            out[key] = copy.deepcopy(value)
    return out


def apko_config(
    base: dict, name: str, spec: dict, stream: str, package: str | None, variant: str, status: str, eol: str | None
) -> dict:
    v = subst(spec["variants"][variant], stream, package)
    tag = f"{stream}-{variant}" if variant else stream
    extra: dict = {
        "contents": {"packages": v["packages"]},
        "annotations": {
            "org.opencontainers.image.title": f"{name}:{tag}",
            "org.opencontainers.image.description": subst(spec.get("description", name), stream, package),
            f"{ANNOTATION_PREFIX}.stream": stream,
            f"{ANNOTATION_PREFIX}.status": status,
        },
    }
    if eol:
        extra["annotations"][f"{ANNOTATION_PREFIX}.eol"] = eol
    if "entrypoint" in v:
        extra["entrypoint"] = {"command": v["entrypoint"]}
    if "cmd" in v:
        extra["cmd"] = v["cmd"]
    if "environment" in v:
        extra["environment"] = v["environment"]
    return merge(base, extra)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--today", type=dt.date.fromisoformat, default=dt.datetime.now(dt.UTC).date())
    ap.add_argument("--offline", type=Path)
    args = ap.parse_args()

    base = yaml.safe_load((IMAGES / "base.yaml").read_text())
    indexes = load_indexes(args.offline)
    old_catalog = json.loads((OUT / "catalog.json").read_text()) if (OUT / "catalog.json").exists() else {}
    catalog: dict = {"images": {}, "builds": []}
    keep: set[Path] = {OUT / "catalog.json"}

    for spec_path in sorted(IMAGES.glob("*/image.yaml")):
        name = spec_path.parent.name
        spec = yaml.safe_load(spec_path.read_text())
        if not (ROOT / "tests" / name / "test.sh").is_file():
            print(f"error: missing tests/{name}/test.sh", file=sys.stderr)
            return 1
        if spec.get("endoflife"):
            releases = load_releases(spec["endoflife"], args.offline)
        else:
            releases = rolling_releases(spec, indexes)
        available = wolfi_streams(spec, releases, indexes)
        old_streams = old_catalog.get("images", {}).get(name, {}).get("streams", {})
        streams, missing = {}, {}

        for rel in releases:
            stream = rel["name"]
            if stream not in available:
                continue  # older than the newest cycle of a newest-only image
            status, eol = classify(rel, args.today)
            package, why = available[stream]
            if why:
                if status == "supported":
                    missing[stream] = why
                elif stream in old_streams:  # dropped from Wolfi after EOL
                    streams[stream] = {"status": "frozen", "eol": eol}
                continue
            if status == "frozen" and stream not in old_streams:
                continue  # EOL before this image was added: never built
            streams[stream] = {"status": status, "eol": eol}
            if status == "frozen":
                continue
            for variant in spec["variants"]:
                tag = f"{stream}-{variant}" if variant else stream
                path = OUT / name / f"{tag}.apko.yaml"
                path.parent.mkdir(parents=True, exist_ok=True)
                cfg = apko_config(base, name, spec, stream, package, variant, status, eol)
                path.write_text(
                    f"# Generated by scripts/generate.py from images/{name}/image.yaml; do not edit.\n"
                    + yaml.safe_dump(cfg, sort_keys=False)
                )
                lock = path.with_name(f"{tag}.lock.json")
                keep.update({path, lock})
                catalog["builds"].append(
                    {
                        "name": name,
                        "tag": tag,
                        "stream": stream,
                        "variant": variant,
                        # Version tags come from this package's locked version
                        # (none for images without one, e.g. static).
                        "package": package if spec.get("version-tag", True) else None,
                        "status": status,
                        "eol": eol,
                        "config": str(path.relative_to(ROOT)),
                        "lock": str(lock.relative_to(ROOT)),
                    }
                )
        # Streams frozen earlier stay recorded even once endoflife.date drops them.
        for stream, entry in old_streams.items():
            streams.setdefault(stream, {**entry, "status": "frozen"})
        catalog["images"][name] = {
            "endoflife": spec.get("endoflife"),
            "streams": dict(sorted(streams.items(), key=lambda kv: version_key(kv[0]), reverse=True)),
            "missing": missing,
        }

    for stale in sorted(OUT.glob("*/*")):
        if stale not in keep:
            print(f"removing {stale.relative_to(ROOT)}")
            stale.unlink()
    (OUT / "catalog.json").write_text(json.dumps(catalog, indent=2) + "\n")

    for name, img in catalog["images"].items():
        for stream, entry in img["streams"].items():
            print(f"{name} {stream}: {entry['status']} (EOL {entry['eol'] or 'n/a'})")
        for stream, why in img["missing"].items():
            print(f"{name} {stream}: MISSING from Wolfi: {', '.join(why)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
