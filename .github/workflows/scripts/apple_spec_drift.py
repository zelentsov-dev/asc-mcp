import argparse
import hashlib
import json
import re
import sys
import zipfile
from pathlib import Path


MAX_SPEC_BYTES = 64 * 1024 * 1024
MAX_CHANGED_POINTERS = 5000
HTTP_METHODS = {"get", "put", "post", "delete", "patch", "head", "options", "trace"}


def read_spec(path, zipped=False):
    if zipped:
        with zipfile.ZipFile(path) as archive:
            entries = [
                info for info in archive.infolist()
                if re.search(r"(^|/)openapi\.oas[^/]*\.json$", info.filename)
            ]
            if len(entries) != 1 or entries[0].file_size > MAX_SPEC_BYTES:
                raise ValueError("Apple archive must contain exactly one bounded OpenAPI JSON document.")
            with archive.open(entries[0]) as stream:
                raw = stream.read(MAX_SPEC_BYTES + 1)
    else:
        with path.open("rb") as stream:
            raw = stream.read(MAX_SPEC_BYTES + 1)
    if len(raw) > MAX_SPEC_BYTES:
        raise ValueError("OpenAPI document exceeds the size limit.")
    document = json.loads(raw)
    if not isinstance(document.get("paths"), dict) or not isinstance(document.get("info"), dict):
        raise ValueError("OpenAPI document must contain paths and info objects.")
    return raw, document


def operation_index(document):
    operations = {}
    for path, item in document["paths"].items():
        for method, operation in item.items():
            if method not in HTTP_METHODS or not isinstance(operation, dict):
                continue
            identifier = operation.get("operationId")
            if not isinstance(identifier, str) or identifier in operations:
                raise ValueError("OpenAPI operations require unique operation IDs.")
            operations[identifier] = {"method": method.upper(), "path": path, "contract": operation}
    return operations


def changed_pointers(before, after):
    paths = []
    count = 0

    def record(path):
        nonlocal count
        count += 1
        if len(paths) < MAX_CHANGED_POINTERS:
            paths.append(path or "/")

    def walk(left, right, path):
        if type(left) is not type(right):
            record(path)
        elif isinstance(left, dict):
            for key in sorted(left.keys() | right.keys()):
                child = path + "/" + key.replace("~", "~0").replace("/", "~1")
                if key not in left or key not in right:
                    record(child)
                else:
                    walk(left[key], right[key], child)
        elif isinstance(left, list):
            if len(left) != len(right):
                record(path)
            else:
                for index, (old, new) in enumerate(zip(left, right)):
                    walk(old, new, path + "/" + str(index))
        elif left != right:
            record(path)

    walk(before, after, "")
    return paths, count


def compare_specs(pinned_raw, pinned, latest_raw, latest):
    old_operations = operation_index(pinned)
    new_operations = operation_index(latest)
    old_ids = old_operations.keys()
    new_ids = new_operations.keys()
    pointers, pointer_count = changed_pointers(pinned, latest)
    pinned_sha = hashlib.sha256(pinned_raw).hexdigest()
    latest_sha = hashlib.sha256(latest_raw).hexdigest()
    return {
        "status": "unchanged" if pinned_sha == latest_sha else "review_required",
        "pinnedVersion": pinned["info"].get("version"),
        "latestVersion": latest["info"].get("version"),
        "pinnedSHA256": pinned_sha,
        "latestSHA256": latest_sha,
        "pinnedPathCount": len(pinned["paths"]),
        "latestPathCount": len(latest["paths"]),
        "pinnedOperationCount": len(old_operations),
        "latestOperationCount": len(new_operations),
        "addedOperations": sorted(new_ids - old_ids),
        "removedOperations": sorted(old_ids - new_ids),
        "changedOperations": sorted(key for key in old_ids & new_ids if old_operations[key] != new_operations[key]),
        "changedJSONPointers": pointers,
        "changedJSONPointerCount": pointer_count,
        "changedJSONPointersTruncated": pointer_count > len(pointers),
        "sourceURL": "https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip",
    }


def markdown(report):
    def safe(value):
        return str(value).replace("&", "&amp;").replace("`", "&#96;").replace("<", "&lt;").replace("\n", " ").replace("\r", " ")

    lines = [
        "# Latest Apple OpenAPI drift",
        "",
        f"Status: **{report['status']}**",
        "",
        f"Pinned version: `{safe(report['pinnedVersion'])}`; latest version: `{safe(report['latestVersion'])}`.",
        "",
        f"Pinned SHA-256: `{report['pinnedSHA256']}`",
        "",
        f"Latest SHA-256: `{report['latestSHA256']}`",
        "",
        "A changed hash requires a reviewed snapshot and contract update before release. Updating only the hash is not acceptance.",
        "This comparison includes referenced schemas and documentation changes; it does not prove runtime compatibility.",
        "",
    ]
    for key in ["addedOperations", "removedOperations", "changedOperations", "changedJSONPointers"]:
        values = report[key]
        lines.extend([f"## {key} ({len(values)})", ""])
        lines.extend("- `" + safe(value) + "`" for value in values[:100])
        if len(values) > 100:
            lines.append("- Additional entries are available in the JSON report.")
        lines.append("")
    if report["changedJSONPointersTruncated"]:
        lines.append(f"The JSON pointer list is bounded; total changed locations: {report['changedJSONPointerCount']}.")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pinned", type=Path, required=True)
    parser.add_argument("--latest-zip", type=Path, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    args = parser.parse_args()
    pinned_raw, pinned = read_spec(args.pinned)
    latest_raw, latest = read_spec(args.latest_zip, zipped=True)
    report = compare_specs(pinned_raw, pinned, latest_raw, latest)
    args.output_directory.mkdir(parents=True, exist_ok=True)
    (args.output_directory / "latest-report.json").write_text(json.dumps(report, indent=2) + "\n")
    (args.output_directory / "latest-report.md").write_text(markdown(report))
    print("Latest Apple OpenAPI: " + report["status"])
    return 0 if report["status"] == "unchanged" else 1


if __name__ == "__main__":
    sys.exit(main())
