"""Make the input net type explicit in the clean Block testbench templates."""

import argparse
import csv
from pathlib import Path
import re
from tempfile import NamedTemporaryFile


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CSV = Path("Data/nl2sva_block.csv")
DEFAULT_NETTYPE_NONE = re.compile(rb"(?m)^[ \t]*`default_nettype[ \t]+none\b")
INPUT_LOGIC = re.compile(rb"(?m)^([ \t]*input[ \t]+)(logic\b)")


def repair_block_testbenches(repo, csv_path=DEFAULT_CSV, *, dry_run=False):
    """Update each CSV-referenced clean template once and return a change count."""
    repo = Path(repo).resolve()
    data = (repo / "Data").resolve()
    with (repo / csv_path).open(encoding="utf-8-sig", newline="") as stream:
        paths = dict.fromkeys(row["testbench"] for row in csv.DictReader(stream))

    changes = []
    for value in paths:
        path = (repo / value).resolve()
        if (not path.is_relative_to(data) or path.parent.name != "tb"
                or path.suffix != ".sv" or not path.is_file()):
            raise ValueError(f"Expected an existing clean Block testbench under Data/<design>/tb/: {value}")
        original = path.read_bytes()
        if not DEFAULT_NETTYPE_NONE.search(original):
            continue
        updated, count = INPUT_LOGIC.subn(rb"\1wire \2", original)
        if count:
            changes.append((path, updated, count))

    for path, updated, count in changes:
        if not dry_run:
            with NamedTemporaryFile(dir=path.parent, delete=False) as stream:
                temporary = Path(stream.name)
                stream.write(updated)
            try:
                temporary.chmod(path.stat().st_mode & 0o777)
                temporary.replace(path)
            finally:
                temporary.unlink(missing_ok=True)
        print(f"{'Would update' if dry_run else 'Updated'} {path.relative_to(repo)}: {count} ports")
    counts = {"templates": len(paths), "changed_templates": len(changes),
              "ports": sum(count for _, _, count in changes)}
    print(f"Block testbenches: {counts['changed_templates']} of {counts['templates']} templates, "
          f"{counts['ports']} explicit input net declarations.", flush=True)
    return counts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    parser.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    repair_block_testbenches(args.repo_root, args.csv, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
