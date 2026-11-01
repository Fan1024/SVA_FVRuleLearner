"""Install this package and remove its superseded typed-PEC adapter.

Run from the extracted package: python apply_signal_list_update.py /path/to/repo
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import shutil

OBSOLETE_FILES = (
    'new_agent/typed_pec.py',
    'tests/test_pec_array_context.py',
    'tests/test_pec_source_bytes.py',
    'requirements_pec_compilation.txt',
    'README_PEC_COMPILATION_UPDATE.md',
    'README_REQUIREMENT_DIAGNOSIS_UPDATE.md',
    'MANIFEST_REQUIREMENT_DIAGNOSIS_UPDATE.json',
    'MANIFEST_PEC_COMPILATION_UPDATE.json',
)


def apply_update(repo, package=None):
    repo = Path(repo).expanduser().resolve()
    package = Path(package or Path(__file__).resolve().parent).resolve()
    config_path = repo / 'new_agent' / 'config.py'
    if not config_path.is_file() or not (repo / 'FVEval' / 'fv_eval' / 'evaluation.py').is_file():
        raise ValueError('Target must be the existing SVA_FVRuleLearner repository root.')
    manifest = json.loads((package / 'MANIFEST_SIGNAL_LIST_UPDATE.json').read_text())
    backup = repo / ('signal_list_backup_' + datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%fZ'))
    copy_paths = [item['path'] for item in manifest['files']]
    cached = list((repo / 'new_agent' / '__pycache__').glob('typed_pec.*.pyc'))
    for relative in dict.fromkeys(copy_paths + list(OBSOLETE_FILES) + ['new_agent/config.py', 'MANIFEST_SIGNAL_LIST_UPDATE.json'] +
                                  [str(path.relative_to(repo)) for path in cached]):
        target = repo / relative
        if target.is_file():
            saved = backup / relative
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target, saved)
    for relative in copy_paths:
        source, target = package / relative, repo / relative
        if source.resolve() == target.resolve():
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    metadata = package / 'MANIFEST_SIGNAL_LIST_UPDATE.json'
    if metadata.resolve() != (repo / metadata.name).resolve():
        shutil.copy2(metadata, repo / metadata.name)
    for relative in OBSOLETE_FILES:
        path = repo / relative
        if path.is_file():
            path.unlink()
    for path in cached:
        path.unlink()
    # Change only this setting; preserve models, datasets, splits and credentials.
    config = config_path.read_text()
    config = config.replace(
        '# Preserve packed ranges, signedness and evaluated TB parameters in native PEC.\n'
        '# "legacy" and "expanded_names" remain available for baseline comparisons.\n',
        '# Expand the native signal-name argument with declared TB signals.\n'
        '# Native PEC/Tcl files remain untouched. "legacy" keeps the original name list.\n')
    replacement = 'PEC_CONTEXT_MODE = "expanded_names"'
    if re.search(r'(?m)^PEC_CONTEXT_MODE\s*=', config):
        config = re.sub(r'(?m)^PEC_CONTEXT_MODE\s*=.*$', replacement, config)
    else:
        config = config.rstrip() + '\n\n' + replacement + '\n'
    config_path.write_text(config)
    return backup


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repo', type=Path, help='Existing SVA_FVRuleLearner checkout')
    args = parser.parse_args()
    backup = apply_update(args.repo)
    print('Installed native signal-list update; removed the typed PEC adapter.')
    print('PEC_CONTEXT_MODE = "expanded_names"; other experiment settings preserved.')
    print(f'Previous files saved in: {backup}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
