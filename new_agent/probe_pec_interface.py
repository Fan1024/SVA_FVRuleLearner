"""Probe native PEC declaration-entry compatibility on the server, without LLM calls.

Never decrypt or rewrite native files. Failed trials leave production names-only.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from new_agent.formal_check import REPO_ROOT, _execution_status

PROFILES = ('range_fragments', 'full_declarations')
CONTROL_NAMES = ('packed_index_self', 'vector_negative', 'array_self',
                 'array_negative', 'signed_positive', 'ascending_positive', 'one_bit_index_self')


def controls(profile=None):
    def entry(name, dimensions='', signed=False, unpacked=''):
        if profile is None:
            return name
        prefix = 'logic ' if profile == 'full_declarations' else ''
        prefix += 'signed ' if signed else ''
        return prefix + (dimensions+' ' if dimensions else '') + name + (' '+unpacked if unpacked else '')
    return [
        ('packed_index_self', 'data[idx]', 'data[idx]',
         [entry('data','[3:0]'), entry('idx','[1:0]')], True),
        ('vector_negative', "data == 4'h1", "data != 4'h0", [entry('data','[3:0]')], False),
        ('array_self', '|items[0]', '|items[0]', [entry('items','[1:0]',unpacked='[0:0]')], True),
        ('array_negative', 'items[0][0]', '(items[0][0] || items[0][1])',
         [entry('items','[1:0]',unpacked='[0:0]')], False),
        ('signed_positive', '(s < 0)', "s[3] == 1'b1", [entry('s','[3:0]',signed=True)], True),
        ('ascending_positive', 'up[0]', "((up >> 3) & 4'h1) != 4'h0", [entry('up','[0:3]')], True),
        ('one_bit_index_self', 'one[idx]', 'one[idx]',
         [entry('one','[0:0]'), entry('idx','[1:0]')], True),
    ]


def run_control(root, label, left, right, entries, expect_equal, timeout, jg):
    directory = root / label
    directory.mkdir(parents=True)
    script = directory / 'probe.tcl'
    # This is a separate probe entry point. No installed/native Tcl is changed.
    script.write_text('''clear -all
include tool_scripts/pec/pec.tcle
if {[catch {info args prop_eq_checker} signature]} {
    set signature "unavailable: $signature"
}
binary scan $signature H* signature_hex
puts "FVRULE_INTERFACE_ARGUMENTS_HEX $signature_hex"
set signal_list [split $SIGNAL_LIST ","]
prop_eq_checker $LM_ASSERT_TEXT $REF_ASSERT_TEXT "" "" $signal_list
''')
    command = [jg,'-fpv','-batch','-tcl',str(script),
               '-define','LM_ASSERT_TEXT',left,'-define','REF_ASSERT_TEXT',right,
               '-define','SIGNAL_LIST',','.join(entries),
               '-define','EXP_ID','pec_interface','-define','TASK_ID',label,
               '-define','SV_DIR',str(directory),
               '-proj',str(directory/'jg'/('pec_interface_'+label)),'-allow_unsupported_OS']
    try:
        completed = subprocess.run(command, cwd=REPO_ROOT/'FVEval', capture_output=True,
                                   text=True, errors='replace', timeout=timeout)
        output = completed.stdout + '\n' + completed.stderr
        status = _execution_status(output)
        returncode = completed.returncode
    except subprocess.TimeoutExpired as error:
        parts = [part.decode(errors='replace') if isinstance(part,bytes) else part or ''
                 for part in (error.stdout,error.stderr)]
        output, status, returncode = '\n'.join(parts), 'TIMEOUT', None
    except OSError as error:
        output, status, returncode = f'{type(error).__name__}: {error}', 'TOOL_ERROR', None
    (directory/'jasper.log').write_text(output)
    signature = None
    match = re.search(r'^FVRULE_INTERFACE_ARGUMENTS_HEX ([0-9a-fA-F]+)\s*$', output,re.M)
    if match:
        signature = bytes.fromhex(match[1]).decode(errors='replace')
    # Reject tool errors even when a partial log happens to contain a verdict.
    passed = (returncode == 0 and
              (status == 'FULL_EQUIVALENCE' if expect_equal else status in {'IMPLIES','NO_EQUIVALENCE'}))
    result = {'name':label,'left':left,'right':right,'signal_entries':entries,
              'expect_equal':expect_equal,'status':status,'returncode':returncode,
              'passed':passed,'runtime_signature':signature,'log':str(directory/'jasper.log')}
    (directory/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    print(f'{label}: {status} | control_passed={passed}',flush=True)
    return result


def profile_verified(results):
    return (len(results) == len(CONTROL_NAMES) and
            [item['control'] for item in results] == list(CONTROL_NAMES) and
            all(item['passed'] is True for item in results))


def probe(output, report_path, timeout=60, jg='jg'):
    checker = REPO_ROOT/'FVEval'/'tool_scripts'/'pec'/'pec.tcle'
    if not checker.is_file():
        raise FileNotFoundError(f'Native checker missing: {checker}')
    output = Path(output).resolve()
    output.mkdir(parents=True,exist_ok=False)
    report_path = Path(report_path).resolve()
    report_path.parent.mkdir(parents=True,exist_ok=True)
    report = {'schema_version':1,'verified':False,'verified_profile':None,
              'checker_sha256':hashlib.sha256(checker.read_bytes()).hexdigest(),
              'baseline':[],'profiles':{},'output_directory':str(output),
              'scope':'Empirical declaration-entry compatibility, not a documented vendor guarantee.'}
    # Invalidate an earlier capability record before trying another checker/session.
    report_path.write_text(json.dumps(report,indent=2)+'\n')
    for label,left,right,entries,equal in (
            ('scalar_self','a','a',['a'],True),
            ('scalar_negative','a','(a || b)',['a','b'],False)):
        report['baseline'].append(run_control(output,label,left,right,entries,equal,timeout,jg))
    print('Native PEC procedure arguments: ' + str(report['baseline'][0]['runtime_signature']),flush=True)
    report['baseline_passed'] = all(item['passed'] for item in report['baseline'])
    if report['baseline_passed']:
        for profile in PROFILES:
            results = []
            for label,left,right,entries,equal in controls(profile):
                item = run_control(output,profile+'_'+label,left,right,entries,equal,timeout,jg)
                item['control'] = label
                results.append(item)
                if not item['passed']:
                    break
            report['profiles'][profile] = results
            if profile_verified(results):
                report.update(verified=True,verified_profile=profile)
                break
    report['conclusion'] = ('Verified declaration profile; production may use it for representable TB types.'
                            if report['verified'] else
                            'No declaration profile verified. Keep the existing name-only native PEC interface unchanged.')
    if not report['baseline_passed']:
        report['conclusion'] = 'Scalar baseline failed: interface probe is inconclusive. Keep names-only and inspect the probe logs.'
    for path in (report_path, output/'probe_result.json'):
        path.write_text(json.dumps(report,indent=2)+'\n')
    print(report['conclusion'],flush=True)
    print(f'Capability report: {report_path}',flush=True)
    print(f'Probe results: {output}',flush=True)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--timeout',type=float,default=60)
    parser.add_argument('--jg',default='jg')
    parser.add_argument('--output-dir',type=Path)
    parser.add_argument('--report',type=Path,default=Path(__file__).with_name('pec_interface_probe.json'))
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    output = args.output_dir or (Path(__file__).parent/'runs'/
        ('PEC_interface_probe_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%fZ')))
    probe(output,args.report,args.timeout,args.jg)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
