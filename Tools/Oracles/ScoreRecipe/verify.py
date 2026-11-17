#!/usr/bin/env python3
"""Compile the Swift oracle and check the independent cross-platform literal pins."""
import argparse
import pathlib
import re
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--build-dir", required=True, type=pathlib.Path)
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[3]
build = args.build_dir.resolve()
with tempfile.TemporaryDirectory(prefix="score-recipe-oracle-") as scratch:
    scratch = pathlib.Path(scratch)
    objects = sorted(str(p) for name in ("StrandAnalytics", "WhoopProtocol", "WhoopStore", "OuraProtocol", "GRDB")
                     for p in (build / (name + ".build")).glob("*.o"))
    if not objects:
        parser.error("No compiled package objects in --build-dir")
    sqlite_module = root / "Packages/WhoopStore/.build/checkouts/GRDB.swift/Sources/CSQLite"
    for parent in build.parents:
        candidate = parent / "checkouts/GRDB.swift/Sources/CSQLite"
        if candidate.is_dir():
            sqlite_module = candidate
            break
    executable = scratch / "oracle"
    subprocess.run(["swiftc", "-module-cache-path", str(scratch / "module-cache"), "-I", str(build / "Modules"),
                    "-I", str(sqlite_module), str(root / "Tools/Oracles/ScoreRecipe/Fixtures.swift"),
                    str(root / "Tools/Oracles/ScoreRecipe/main.swift"), *objects, "-lsqlite3", "-o", str(executable)], check=True)
    actual = subprocess.check_output([str(executable)], text=True).strip()
    swift = (root / "Packages/StrandAnalytics/Tests/StrandAnalyticsTests/ScoreRecipeTests.swift").read_text()
    kotlin = (root / "android/app/src/test/java/com/noop/analytics/ScoreRecipeTest.kt").read_text()
    swift_pin = re.search(r'private static let swiftOracle = """\n(.*?)\n"""', swift, re.S).group(1)
    kotlin_pin = re.search(r'val SWIFT_ORACLE = """(.*?)"""', kotlin, re.S).group(1)
    assert actual == swift_pin == kotlin_pin, "Compiled Swift oracle differs from cross-platform literal pins"
    print(actual)
