"""Unit tests for scripts/generate.py: python3 -m unittest discover tests/generator"""

import datetime as dt
import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "generate.py"
spec = importlib.util.spec_from_file_location("generate", SCRIPT)
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)

TODAY = dt.date(2026, 11, 19)


def epoch(days_ago: int) -> int:
    day = TODAY - dt.timedelta(days=days_ago)
    return int(dt.datetime(day.year, day.month, day.day, tzinfo=dt.UTC).timestamp())


def index(packages: dict[str, tuple[str, int]]):
    """{name: (version, days since build)} on every architecture."""
    gen.BUILD_TIMES.clear()
    indexes = {}
    for arch in gen.ARCHS:
        indexes[arch] = {name: [version] for name, (version, _) in packages.items()}
        gen.BUILD_TIMES[arch] = {name: epoch(age) for name, (_, age) in packages.items()}
    return indexes


class MaintenanceTest(unittest.TestCase):
    def test_stale_rolling_package_is_maintained(self):
        # glibc: no rebuild for 100 days, but every listed fix is published.
        spec = {"stream": "latest", "package": "glibc", "variants": {"": {"packages": ["glibc"]}}}
        indexes = index({"glibc": ("2.43-r13", 100)})
        result = gen.wolfi_streams(spec, [{"name": "latest"}], indexes, {"glibc": ["2.43-r10"]}, TODAY)
        self.assertEqual(result, {"latest": ("glibc", [])})

    def test_rolling_package_with_unpublished_fix_is_unmaintained(self):
        spec = {"stream": "latest", "package": "glibc", "variants": {"": {"packages": ["glibc"]}}}
        indexes = index({"glibc": ("2.43-r13", 5)})
        result = gen.wolfi_streams(spec, [{"name": "latest"}], indexes, {"glibc": ["2.43-r14"]}, TODAY)
        self.assertEqual(
            result["latest"][1], ["unmaintained: Wolfi lists fixes up to 2.43-r14 but publishes 2.43-r13 (x86_64)"]
        )

    def test_stale_versioned_stream_is_unmaintained(self):
        # nodejs-22: Wolfi stopped building it while nodejs-24 is current.
        spec = {"package": "nodejs-{stream}", "variants": {"": {"packages": ["nodejs-{stream}"]}}}
        indexes = index({"nodejs-22": ("22.23.2-r1", 104), "nodejs-24": ("24.22.3-r2", 7)})
        result = gen.wolfi_streams(spec, [{"name": "24"}, {"name": "22"}], indexes, {}, TODAY)
        self.assertEqual(result["24"], ("nodejs-24", []))
        self.assertEqual(result["22"][0], "nodejs-22")
        self.assertRegex(result["22"][1][0], r"104 days old \(limit 90\)")

    def test_max_age_days_overrides_the_limit(self):
        spec = {"package": "nodejs-{stream}", "max-age-days": 120, "variants": {"": {"packages": ["nodejs-{stream}"]}}}
        indexes = index({"nodejs-22": ("22.23.2-r1", 104)})
        result = gen.wolfi_streams(spec, [{"name": "22"}], indexes, {}, TODAY)
        self.assertEqual(result["22"], ("nodejs-22", []))


if __name__ == "__main__":
    unittest.main()
