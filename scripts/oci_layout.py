#!/usr/bin/env python3
"""Turn an `apko build` tarball into an OCI image layout, keeping digests.

apko writes a docker-loadable tarball whose index.json *is* the multi-arch
image index. This stores those exact bytes as the index blob and points a new
layout index.json at it, so `regctl image copy ocidir://<dir>@<digest> ...`
pushes the image with the same digest that was built and tested.

Usage: oci_layout.py <apko.tar> <layout-dir>   (prints the index digest)
"""

import hashlib
import json
import re
import sys
import tarfile
from pathlib import Path


def main() -> int:
    src, dest = Path(sys.argv[1]), Path(sys.argv[2])
    blobs = dest / "blobs" / "sha256"
    blobs.mkdir(parents=True, exist_ok=True)
    index = None
    with tarfile.open(src) as tar:
        for member in tar.getmembers():
            if not member.isfile():
                continue
            data = tar.extractfile(member).read()
            name = member.name
            if name == "index.json":
                index = data
                continue
            if name == "manifest.json":
                continue  # docker-load metadata only
            m = re.fullmatch(r"(?:sha256:)?([0-9a-f]{64})(?:\.tar\.gz)?", name)
            if not m:
                raise SystemExit(f"unexpected tar member: {name}")
            if hashlib.sha256(data).hexdigest() != m.group(1):
                raise SystemExit(f"digest mismatch for {name}")
            (blobs / m.group(1)).write_bytes(data)
    if index is None:
        raise SystemExit("no index.json in tarball")

    digest = hashlib.sha256(index).hexdigest()
    (blobs / digest).write_bytes(index)
    for desc in json.loads(index)["manifests"]:
        if not (blobs / desc["digest"].removeprefix("sha256:")).is_file():
            raise SystemExit(f"index references missing manifest {desc['digest']}")
    layout_index = {
        "schemaVersion": 2,
        "mediaType": "application/vnd.oci.image.index.v1+json",
        "manifests": [
            {
                "mediaType": "application/vnd.oci.image.index.v1+json",
                "digest": f"sha256:{digest}",
                "size": len(index),
            }
        ],
    }
    (dest / "index.json").write_text(json.dumps(layout_index))
    (dest / "oci-layout").write_text('{"imageLayoutVersion":"1.0.0"}')
    print(f"sha256:{digest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
