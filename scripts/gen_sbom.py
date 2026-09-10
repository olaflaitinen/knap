# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : scripts/gen_sbom.py
# Purpose     : Generates the CycloneDX software bill of materials from the
#               resolved lock file, and checks the committed copy is current.
# Stage       : Supply chain transparency. See docs/PACKAGING.md
# Depends on  : uv.lock, pyproject.toml. Python standard library only.
# Invariants  : Output is deterministic. Nothing in it depends on the clock,
#               the machine, or the order a dictionary happened to iterate in,
#               so a rerun on an unchanged tree produces a byte identical file.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
"""Generate the Knap software bill of materials in CycloneDX 1.6 format.

A bill of materials answers one question for the person deciding whether to
depend on this project: when the next advisory lands against some package,
does it reach me through Knap. For most projects that answer takes an
afternoon of reading lock files. This file makes it a grep.

Knap's answer is unusually short, and the shape of the document says so.
The distributed artefact is compiled Mojo. It links no Python, embeds no
vocabulary, and calls out to nothing at run time, so its runtime dependency
set is empty. That fact is recorded on the root component as a property
rather than left to be inferred from an absence.

What the components list holds is therefore the build and development
environment, split in two by CycloneDX scope. "required" is what the pinned
Mojo toolchain pulls in, without which the artefact cannot be produced.
"excluded" is what is present only for testing and benchmarking, which is
the standard's way of recording a component that exists in the development
environment and reaches no consumer.

That distinction is the point. A bill of materials that lists a project's
test dependencies as though they were shipped tells a reader the opposite of
the truth, and it is the most common way these documents mislead. So does
one that lists a compiler as though the compiled output still depended on
it, which is why the runtime set is stated outright.

Determinism is a requirement rather than a nicety, because the committed
copy is gated the same way the other generated files are. There is no
timestamp: CycloneDX makes it optional, and a field that changes on every run
would make the drift check permanently red. The document's serial number is
derived from the project name and version rather than drawn at random, so
regenerating an unchanged tree reproduces the same file byte for byte.

    python scripts/gen_sbom.py
    python scripts/gen_sbom.py --check

Exit status is 0 when the committed file is current, and 1 when it is stale.
"""

from __future__ import annotations

import argparse
import json
import sys
import uuid
from pathlib import Path

# tomllib entered the standard library in Python 3.11. The project's own
# environment is newer than that, but pyproject.toml declares support from
# 3.10, so the failure is named rather than left as a bare ImportError.
try:
    import tomllib
except ModuleNotFoundError as exc:  # pragma: no cover, version dependent
    raise SystemExit(
        "gen_sbom: needs Python 3.11 or newer for tomllib."
    ) from exc

REPO_ROOT = Path(__file__).resolve().parent.parent

LOCK_FILE = REPO_ROOT / "uv.lock"
PROJECT_FILE = REPO_ROOT / "pyproject.toml"
OUTPUT_FILE = REPO_ROOT / "sbom.cdx.json"

# The specification this document claims to follow. Bumping it is a decision
# about what consumers can parse, not a routine upgrade.
SPEC_VERSION = "1.6"

REPOSITORY_URL = "https://github.com/olaflaitinen/knap"
LICENCE_ID = "EUPL-1.2"

# CycloneDX scopes used here. "required" means the component is needed to
# build the artefact, which is the pinned compiler and whatever it pulls in;
# "excluded" means it is present during development, for tests and
# benchmarks, and reaches no consumer. Neither means the compiled binary
# depends on it at run time, and nothing does: that is stated as a property
# on the root component. There is no third case in this project, and a
# component that fitted neither would be a bug in this script rather than a
# reason to invent a category.
SCOPE_REQUIRED = "required"
SCOPE_EXCLUDED = "excluded"

# A fixed namespace, so that the serial number is a function of the project
# rather than of when the generator ran. Any UUID would do provided it never
# changes; this one is the DNS namespace applied to the repository host.
SERIAL_NAMESPACE = uuid.uuid5(uuid.NAMESPACE_DNS, "knap.olaflaitinen.github")


def load_toml(path: Path) -> dict:
    """Read one TOML file.

    Args:
        path: The file to read.

    Returns:
        Its parsed contents.

    Raises:
        SystemExit: if the file is missing or will not parse. Both are
            reported rather than defaulted, because a bill of materials
            assembled from a partially readable lock file would be worse
            than no bill at all.
    """
    try:
        with path.open("rb") as handle:
            return tomllib.load(handle)
    except OSError as exc:
        raise SystemExit(f"gen_sbom: cannot read {path.name}: {exc}") from exc
    except tomllib.TOMLDecodeError as exc:
        raise SystemExit(f"gen_sbom: {path.name} will not parse: {exc}") from exc


def package_index(lock: dict) -> dict[str, dict]:
    """Index the lock file's packages by name.

    Args:
        lock: The parsed lock file.

    Returns:
        Every locked package, keyed by its name.
    """
    return {entry["name"]: entry for entry in lock.get("package", [])}


def reachable_from(
    roots: list[str], packages: dict[str, dict]
) -> set[str]:
    """Return every package reachable from the given roots.

    Args:
        roots: Package names to start from.
        packages: The package index.

    Returns:
        The transitive closure, including the roots themselves.

    Markers are deliberately ignored. A dependency that only applies below
    Python 3.11 is still a dependency somebody's environment will resolve,
    and a bill of materials that hides it because this machine did not need
    it is a bill of materials that is wrong on another machine.
    """
    seen: set[str] = set()
    pending = list(roots)
    while pending:
        name = pending.pop()
        if name in seen or name not in packages:
            continue
        seen.add(name)
        for edge in packages[name].get("dependencies", []):
            pending.append(edge["name"])
    return seen


def source_hash(entry: dict) -> list[dict[str, str]]:
    """Extract the source distribution digest, when the lock file has one.

    Args:
        entry: One locked package.

    Returns:
        A CycloneDX hash list, empty when the package is wheel only.

    Only the source distribution digest is recorded. Wheel digests are per
    platform and per Python version, so listing them would make this document
    describe one machine's download set rather than the dependency itself.
    """
    sdist = entry.get("sdist", {})
    digest = sdist.get("hash", "")
    if not digest.startswith("sha256:"):
        return []
    return [{"alg": "SHA-256", "content": digest.split(":", 1)[1]}]


def component_for(entry: dict, scope: str) -> dict:
    """Build one CycloneDX component from a locked package.

    Args:
        entry: One locked package.
        scope: The CycloneDX scope to record.

    Returns:
        The component object.
    """
    name = entry["name"]
    version = entry["version"]
    component: dict = {
        "type": "library",
        "bom-ref": f"pkg:pypi/{name}@{version}",
        "name": name,
        "version": version,
        "purl": f"pkg:pypi/{name}@{version}",
        "scope": scope,
    }
    hashes = source_hash(entry)
    if hashes:
        component["hashes"] = hashes
    return component


def dependency_edges(
    names: list[str], packages: dict[str, dict]
) -> list[dict]:
    """Build the CycloneDX dependency graph for the given packages.

    Args:
        names: Package names to emit edges for, in the order they appear.
        packages: The package index.

    Returns:
        One entry per package, each naming the references it depends on.
    """
    edges = []
    for name in names:
        entry = packages[name]
        reference = f"pkg:pypi/{name}@{entry['version']}"
        depends = []
        for edge in entry.get("dependencies", []):
            child = edge["name"]
            if child in packages:
                depends.append(
                    f"pkg:pypi/{child}@{packages[child]['version']}"
                )
        edges.append(
            {"ref": reference, "dependsOn": sorted(set(depends))}
        )
    return edges


def build_document() -> dict:
    """Assemble the whole bill of materials.

    Returns:
        The CycloneDX document, ready to serialise.

    Raises:
        SystemExit: if the lock file does not contain the project itself,
            which would mean the lock is out of step with pyproject.toml.
    """
    lock = load_toml(LOCK_FILE)
    project = load_toml(PROJECT_FILE)["project"]
    packages = package_index(lock)

    name = project["name"]
    version = project["version"]
    if name not in packages:
        raise SystemExit(
            f"gen_sbom: {name} is not in uv.lock. Run 'uv lock' first."
        )

    root_entry = packages[name]
    runtime_roots = [
        edge["name"] for edge in root_entry.get("dependencies", [])
    ]
    development_roots = [
        edge["name"]
        for group in root_entry.get("dev-dependencies", {}).values()
        for edge in group
    ]

    required = reachable_from(runtime_roots, packages)
    development = reachable_from(development_roots, packages) - required

    # Sorted, because the lock file's order is an implementation detail of
    # the resolver and this document has to be stable across resolutions.
    listed = sorted(required | development)

    components = [
        component_for(
            packages[dependency],
            SCOPE_REQUIRED if dependency in required else SCOPE_EXCLUDED,
        )
        for dependency in listed
    ]

    root_reference = f"pkg:generic/{name}@{version}"
    dependencies = [
        {
            "ref": root_reference,
            "dependsOn": sorted(
                f"pkg:pypi/{dependency}@{packages[dependency]['version']}"
                for dependency in runtime_roots
            ),
        }
    ]
    dependencies.extend(dependency_edges(listed, packages))

    serial = uuid.uuid5(SERIAL_NAMESPACE, f"{name}@{version}")

    return {
        "bomFormat": "CycloneDX",
        "specVersion": SPEC_VERSION,
        "serialNumber": f"urn:uuid:{serial}",
        "version": 1,
        "metadata": {
            "tools": {
                "components": [
                    {
                        "type": "application",
                        "name": "gen_sbom.py",
                        "version": version,
                    }
                ]
            },
            "authors": [
                {
                    "name": author["name"],
                    "email": author["email"],
                }
                for author in project.get("authors", [])
            ],
            "component": {
                "type": "library",
                "bom-ref": root_reference,
                "name": name,
                "version": version,
                "description": project["description"],
                "purl": root_reference,
                "licenses": [{"license": {"id": LICENCE_ID}}],
                "externalReferences": [
                    {"type": "vcs", "url": REPOSITORY_URL},
                    {"type": "website", "url": "https://knap.lovable.app"},
                ],
                "properties": [
                    {
                        "name": "knap:runtime-dependencies",
                        "value": "none",
                    },
                    {
                        "name": "knap:runtime-interpreter",
                        "value": "none",
                    },
                    {
                        "name": "knap:vocabularies-bundled",
                        "value": "none",
                    },
                ],
            },
        },
        "components": components,
        "dependencies": dependencies,
    }


def render(document: dict) -> str:
    """Serialise the document the one way this project writes JSON.

    Args:
        document: The assembled bill of materials.

    Returns:
        The file's exact intended contents, newline terminated.
    """
    return json.dumps(document, indent=2, sort_keys=True) + "\n"


def main() -> int:
    """Write the bill of materials, or report that the committed copy drifted.

    Returns:
        0 when the committed file is current or was written, 1 when stale.
    """
    parser = argparse.ArgumentParser(
        description="Generate the Knap CycloneDX bill of materials."
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Do not write. Exit non zero if the committed file is stale.",
    )
    arguments = parser.parse_args()

    expected = render(build_document())

    if arguments.check:
        if not OUTPUT_FILE.exists():
            print(
                "gen_sbom: sbom.cdx.json is missing. Run "
                "'python scripts/gen_sbom.py'.",
                file=sys.stderr,
            )
            return 1
        actual = OUTPUT_FILE.read_text(encoding="utf-8")
        if actual != expected:
            print(
                "gen_sbom: sbom.cdx.json does not match uv.lock. Run "
                "'python scripts/gen_sbom.py'.",
                file=sys.stderr,
            )
            return 1
        print("gen_sbom: sbom.cdx.json is current.")
        return 0

    OUTPUT_FILE.write_text(expected, encoding="utf-8")
    document = json.loads(expected)
    required = sum(
        1
        for component in document["components"]
        if component["scope"] == SCOPE_REQUIRED
    )
    excluded = len(document["components"]) - required
    print(
        f"gen_sbom: wrote sbom.cdx.json, {required} required and "
        f"{excluded} excluded components."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

# =============================================================================
# End of file: scripts/gen_sbom.py
# =============================================================================
