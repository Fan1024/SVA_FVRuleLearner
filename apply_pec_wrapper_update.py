"""Install only the PEC wrapper/probe; undo exact known v7 policy edits from backups."""
from datetime import datetime, timezone
import argparse
import hashlib
import json
from pathlib import Path
import shutil


def source_hash(path):
    return hashlib.sha256(Path(path).read_text().replace('\r\n','\n').rstrip().encode()).hexdigest()


def apply_update(repo, package=None):
    repo = Path(repo).expanduser().resolve()
    package = Path(package or Path(__file__).parent).resolve()
    if not (repo/'new_agent'/'config.py').is_file():
        raise ValueError('Target must be the existing repository root.')
    manifest_path = package/'MANIFEST_PEC_WRAPPER_ONLY.json'
    if not manifest_path.is_file():
        raise ValueError('Use this installer beside the manifest and complete extracted package.')
    manifest = json.loads(manifest_path.read_text())
    previous = sorted(repo.glob('signal_list_backup_*'),reverse=True)
    backup = repo/('pec_wrapper_backup_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%fZ'))
    restored, unresolved = [], []
    for relative, incorrect_hash in manifest.get('undo_known_v7_edits',{}).items():
        target=repo/relative
        if not target.is_file() or source_hash(target)!=incorrect_hash:
            continue
        original = next((folder/relative for folder in previous
                         if (folder/relative).is_file() and source_hash(folder/relative)!=incorrect_hash),None)
        if original is None:
            unresolved.append(relative)
            continue
        saved=backup/relative
        saved.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(target,saved)
        shutil.copy2(original,target)
        restored.append(relative)
    for item in manifest['files']:
        relative=item['path']
        # Runtime installation is deliberately restricted to these two modules.
        if relative not in {'new_agent/pec_context_adapter.py','new_agent/probe_pec_interface.py',
                             'tests/test_pec_interface_probe.py'}:
            continue
        source,target=package/relative,repo/relative
        if source.resolve()==target.resolve():
            continue
        if target.is_file():
            saved=backup/relative
            saved.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(target,saved)
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(source,target)
    return {'restored_previous_files':restored,'unresolved_v7_files':unresolved,'backup':str(backup)}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repo',type=Path)
    args=parser.parse_args()
    result=apply_update(args.repo)
    print('Installed PEC wrapper and probe only. No new experiment or acceptance policy is installed.')
    if result['restored_previous_files']:
        print('Undid my known v7 experiment edits using your pre-update backups:')
        for path in result['restored_previous_files']:
            print('  '+path)
    if result['unresolved_v7_files']:
        print('Known v7 edits found without a prior backup; these were left untouched:')
        for path in result['unresolved_v7_files']:
            print('  '+path)
    print('Backup: '+result['backup'])
    return 0 if not result['unresolved_v7_files'] else 1


if __name__=='__main__':
    raise SystemExit(main())
