########################################################
# NVIDIA License
#
# 1. Definitions
#
# “Licensor” means any person or entity that distributes its Work.
# “Work” means (a) the original work of authorship made available under this license, which may include software, documentation, or other files, and (b) any additions to or derivative works  thereof  that are made available under this license.
# The terms “reproduce,” “reproduction,” “derivative works,” and “distribution” have the meaning as provided under U.S. copyright law; provided, however, that for the purposes of this license, derivative works shall not include works that remain separable from, or merely link (or bind by name) to the interfaces of, the Work.
# Works are “made available” under this license by including in or with the Work either (a) a copyright notice referencing the applicability of this license to the Work, or (b) a copy of this license.
#
# 2. License Grant
#
# 2.1 Copyright Grant. Subject to the terms and conditions of this license, each Licensor grants to you a perpetual, worldwide, non-exclusive, royalty-free, copyright license to use, reproduce, prepare derivative works of, publicly display, publicly perform, sublicense and distribute its Work and any resulting derivative works in any form.
#
# 3. Limitations
#
# 3.1 Redistribution. You may reproduce or distribute the Work only if (a) you do so under this license, (b) you include a complete copy of this license with your distribution, and (c) you retain without modification any copyright, patent, trademark, or attribution notices that are present in the Work.
#
# 3.2 Derivative Works. You may specify that additional or different terms apply to the use, reproduction, and distribution of your derivative works of the Work (“Your Terms”) only if (a) Your Terms provide that the use limitation in Section 3.3 applies to your derivative works, and (b) you identify the specific derivative works that are subject to Your Terms. Notwithstanding Your Terms, this license (including the redistribution requirements in Section 3.1) will continue to apply to the Work itself.
#
# 3.3 Use Limitation. The Work and any derivative works thereof only may be used or intended for use non-commercially. Notwithstanding the foregoing, NVIDIA Corporation and its affiliates may use the Work and any derivative works commercially. As used herein, “non-commercially” means for research or evaluation purposes only.
#
# 3.4 Patent Claims. If you bring or threaten to bring a patent claim against any Licensor (including any claim, cross-claim or counterclaim in a lawsuit) to enforce any patents that you allege are infringed by any Work, then your rights under this license from such Licensor (including the grant in Section 2.1) will terminate immediately.
#
# 3.5 Trademarks. This license does not grant any rights to use any Licensor’s or its affiliates’ names, logos, or trademarks, except as necessary to reproduce the notices described in this license.
#
# 3.6 Termination. If you violate any term of this license, then your rights under this license (including the grant in Section 2.1) will terminate immediately.
#
# 4. Disclaimer of Warranty.
#
# THE WORK IS PROVIDED “AS IS” WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WARRANTIES OR CONDITIONS OF 
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE OR NON-INFRINGEMENT. YOU BEAR THE RISK OF UNDERTAKING ANY ACTIVITIES UNDER THIS LICENSE. 
#
# 5. Limitation of Liability.
#
# EXCEPT AS PROHIBITED BY APPLICABLE LAW, IN NO EVENT AND UNDER NO LEGAL THEORY, WHETHER IN TORT (INCLUDING NEGLIGENCE), CONTRACT, OR OTHERWISE SHALL ANY LICENSOR BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING OUT OF OR RELATED TO THIS LICENSE, THE USE OR INABILITY TO USE THE WORK (INCLUDING BUT NOT LIMITED TO LOSS OF GOODWILL, BUSINESS INTERRUPTION, LOST PROFITS OR DATA, COMPUTER FAILURE OR MALFUNCTION, OR ANY OTHER DAMAGES OR LOSSES), EVEN IF THE LICENSOR HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.
########################################################
import os
import shutil
import subprocess
import multiprocessing
import pathlib
import re
from config import FLAGS
from saver import saver
import time
import json
import random

from pprint import pformat
from typing import List, Tuple, Dict

ROOT = pathlib.Path(__file__).parent.parent

print = saver.log_info

"""
Methods for launching Cadence Jasper
"""


def launch_jg(
    tcl_file_path: str,
    sv_dir: str,
    experiment_id: str,
    task_id: str,
    iter_id: str = None,
    seq_id: str = None,
    output_queue: multiprocessing.Queue = None,
    CLK:str = None,
    RST:str = None,
    TB_MODULE = None,
    TOP = None,
) -> str:
    if (iter_id is not None) and (seq_id is not None):
        tmp_jg_proj_dir = os.path.join(sv_dir, f"jg")
    else:
        tmp_jg_proj_dir = os.path.join(sv_dir, f"jg")

    jg_command = [
        "jg",
        "-fpv",
        "-batch",
        "-tcl",
        tcl_file_path,
        "-define",
        "EXP_ID",
        experiment_id,
        "-define",
        "TASK_ID",
        task_id,
        "-define",
        "SV_DIR",
        sv_dir,
    ]

    # Include ITER_ID and SEQ_ID if provided
    if iter_id is not None:
        jg_command.extend(["-define", "ITER_ID", iter_id])
    if seq_id is not None:
        jg_command.extend(["-define", "SEQ_ID", seq_id])
    if CLK is not None:
        jg_command.extend(["-define", "CLK", CLK])
    if RST is not None:
        jg_command.extend(["-define", "RST", RST])
    if TB_MODULE is not None:
        jg_command.extend(["-define", "TB_MODULE", TB_MODULE])
    if TOP is not None:
        jg_command.extend(["-define", "TOP", TOP])

    jg_command.extend([
        "-proj",
        tmp_jg_proj_dir,
        "-allow_unsupported_OS",
    ])

    # Run the JasperGold command and capture both stdout and stderr
    result = subprocess.run(
        jg_command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    # result = subprocess.run(jg_command, capture_output=True, text=True)

    # Combine stdout and stderr
    # Combine stdout and stderr
    jasper_output = result.stdout.strip()

    # Write jasper_output to a file
        # Write the command to a file
    with open(os.path.join(sv_dir,"command.txt"), "w") as command_file:
        command_file.write(" ".join(jg_command))
    with open(os.path.join(sv_dir,"output.txt"), "w") as output_file:
        output_file.write(jasper_output)
    # + "\n" + result.stderr.strip()

    # Print the command and outputs for debugging
    # print(f"Running command: {' '.join(jg_command)}")
    # print(f"Return code: {result.returncode}")
    # print(f"stdout:\n{result.stdout}")
    # print(f"stderr:\n{result.stderr}")

    return jasper_output

# def launch_jg_with_queue(
#     tcl_file_path: str,
#     sv_dir: str,
#     experiment_id: str,
#     task_id: str,
#     iter_id: str = None,
#     seq_id: str = None,
#     output_queue: multiprocessing.Queue = None,
# ) -> None:
#     tmp_jg_proj_dir = sv_dir + f"/jg/{experiment_id}_{task_id}"
#     if os.path.isdir(tmp_jg_proj_dir):
#         shutil.rmtree(tmp_jg_proj_dir)
#     jg_command = [
#         "jg",
#         "-fpv",
#         "-batch",
#         "-tcl",
#         tcl_file_path,
#         "-define",
#         "EXP_ID",
#         experiment_id,
#         "-define",
#         "TASK_ID",
#         task_id,
#         "-define",
#         "SV_DIR",
#         sv_dir,
#         "-proj",
#         tmp_jg_proj_dir,
#         "-allow_unsupported_OS",
#     ]
#     result = subprocess.run(jg_command, capture_output=True, text=True)
#     output_queue.put(result.stdout.strip())

# def launch_jg_with_queue(
#     tcl_file_path: str,
#     sv_dir: str,
#     experiment_id: str,
#     task_id: str,
#     iter_id: str = None,
#     seq_id: str = None,
#     output_queue: multiprocessing.Queue = None,
# ) -> None:
#     if (iter_id is not None) and (seq_id is not None):
#         tmp_jg_proj_dir = os.path.join(sv_dir, f"jg/{experiment_id}_{task_id}_{iter_id}_{seq_id}")
#     else:
#         tmp_jg_proj_dir = os.path.join(sv_dir, f"jg/{experiment_id}_{task_id}")

#     if os.path.isdir(tmp_jg_proj_dir):
#         shutil.rmtree(tmp_jg_proj_dir)

#     jg_command = [
#         "jg",
#         "-fpv",
#         "-batch",
#         "-tcl",
#         tcl_file_path,
#         "-define",
#         "EXP_ID",
#         experiment_id,
#         "-define",
#         "TASK_ID",
#         task_id,
#         "-define",
#         "SV_DIR",
#         sv_dir,
#     ]

#     # Include ITER_ID and SEQ_ID if provided
#     if iter_id is not None:
#         jg_command.extend(["-define", "ITER_ID", iter_id])
#     if seq_id is not None:
#         jg_command.extend(["-define", "SEQ_ID", seq_id])

#     jg_command.extend([
#         "-proj",
#         tmp_jg_proj_dir,
#         "-allow_unsupported_OS",
#     ])

#     # Run the JasperGold command and capture both stdout and stderr
#     result = subprocess.run(
#         jg_command,
#         stdout=subprocess.PIPE,
#         stderr=subprocess.PIPE,
#         text=True
#     )

#     # Combine stdout and stderr
#     jasper_output = result.stdout + "\n" + result.stderr
#     # + "\n" + result.stderr.strip()

#     print(f"***DEBUG***: \n{jasper_output}")

#     # Put the output in the queue if provided
#     if output_queue is not None:
#         output_queue.put(jasper_output)

#     # If no queue is provided, return the output (for compatibility with non-queue usage)
#     else:
#         return jasper_output

def launch_jg_with_queue(
    tcl_file_path: str,
    sv_dir: str,
    experiment_id: str,
    task_id: str,
    iter_id: str = None,
    seq_id: str = None,
    output_queue: multiprocessing.Queue = None,
) -> None:
    if (iter_id is not None) and (seq_id is not None):
        tmp_jg_proj_dir = os.path.join(sv_dir, f"jg/{experiment_id}_{task_id}_{iter_id}_{seq_id}")
    else:
        tmp_jg_proj_dir = os.path.join(sv_dir, f"jg/{experiment_id}_{task_id}")

    if os.path.isdir(tmp_jg_proj_dir):
        shutil.rmtree(tmp_jg_proj_dir)

    jg_command = [
        "jg",
        "-fpv",
        "-batch",
        "-tcl",
        tcl_file_path,
        "-define",
        "EXP_ID",
        experiment_id,
        "-define",
        "TASK_ID",
        task_id,
        "-define",
        "SV_DIR",
        sv_dir,
    ]

    # Include ITER_ID and SEQ_ID if provided
    if iter_id is not None:
        jg_command.extend(["-define", "ITER_ID", iter_id])
    if seq_id is not None:
        jg_command.extend(["-define", "SEQ_ID", seq_id])

    jg_command.extend([
        "-proj",
        tmp_jg_proj_dir,
        "-allow_unsupported_OS",
    ])

    # Start the subprocess
    process = subprocess.Popen(
        jg_command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    stdout_data = []
    stderr_data = []

    # Read stdout and stderr incrementally
    for line in iter(process.stdout.readline, ''):
        stdout_data.append(line)
    for line in iter(process.stderr.readline, ''):
        stderr_data.append(line)

    process.stdout.close()
    process.stderr.close()
    process.wait()

    jasper_output = ''.join(stdout_data) + '\n' + ''.join(stderr_data)

    # print(f"***DEBUG***: \n{jasper_output}")

    # Handle the output
    if output_queue is not None:
        output_queue.put(jasper_output)
    else:
        return jasper_output


def launch_jg_custom_equiv_check(
    tcl_file_path: str,
    sv_dir: str,
    experiment_id: str,
    task_id: str,
    lm_assertion_text: str,
    ref_assertion_text: str,
    signal_list_text: str,
    output_queue: multiprocessing.Queue = None,
) -> None:
    tmp_jg_proj_dir = sv_dir + f"/jg/{experiment_id}_{task_id}"
    if os.path.isdir(tmp_jg_proj_dir):
        shutil.rmtree(tmp_jg_proj_dir)
    jg_command = [
        "jg",
        "-fpv",
        "-batch",
        "-tcl",
        tcl_file_path,
        "-define",
        "LM_ASSERT_TEXT",
        lm_assertion_text,
        "-define",
        "REF_ASSERT_TEXT",
        ref_assertion_text,
        "-define",
        "SIGNAL_LIST",
        signal_list_text,
        "-define",
        "EXP_ID",
        experiment_id,
        "-define",
        "TASK_ID",
        task_id,
        "-define",
        "SV_DIR",
        sv_dir,
        "-proj",
        tmp_jg_proj_dir,
        "-allow_unsupported_OS",
    ]

    FVEval_dir = os.path.abspath(os.path.join(os.path.dirname(tcl_file_path), '..'))

    print(f"Executing command in directory: {FVEval_dir}")

    timeout_seconds = getattr(FLAGS, "jg_timeout_seconds", 300)
    try:
        result = subprocess.run(
            jg_command,
            cwd=FVEval_dir,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
        )
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(
            f"JasperGold timed out after {timeout_seconds} seconds "
            f"for task {task_id}"
        ) from exc

    jasper_output = "\n".join(
        part
        for part in (result.stdout.strip(), result.stderr.strip())
        if part
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"JasperGold failed for task {task_id}; "
            f"return code={result.returncode}\n{jasper_output}"
        )

    # DEBUG: Print JasperGold execution details, 1019, to debug the JasperGold output
    # print(f"\n{'='*80}")
    # print(f"DEBUG JG [{experiment_id}_{task_id}]:")
    # print(f"  Return code: {result.returncode}")
    # print(f"  STDOUT length: {len(result.stdout)} chars")
    # print(f"  STDERR length: {len(result.stderr)} chars")
    # if result.returncode != 0:
    #     print(f"  ❌ JG FAILED with return code {result.returncode}")
    #     print(f"  STDERR: {result.stderr if result.stderr else '(empty)'}")
    # if len(result.stdout) < 100:
    #     print(f"  ⚠️  Short output - likely error!")
    #     print(f"  STDOUT: {result.stdout}")
    #     print(f"  STDERR: {result.stderr if result.stderr else '(empty)'}")
    # else:
    #     print(f"  ✓ STDOUT preview: {result.stdout}...")
    # print(f"{'='*80}\n")
    # breakpoint()
    
    # result = subprocess.run(jg_command, capture_output=True, text=True)
    return jasper_output


def launch_jg_with_queue_custom_equiv_check(
    tcl_file_path: str,
    sv_dir: str,
    experiment_id: str,
    task_id: str,
    lm_assertion_text: str,
    ref_assertion_text: str,
    signal_list_text: str,
    output_queue: multiprocessing.Queue = None,
) -> None:
    tmp_jg_proj_dir = sv_dir + f"/jg/{experiment_id}_{task_id}"
    if os.path.isdir(tmp_jg_proj_dir):
        shutil.rmtree(tmp_jg_proj_dir)
    jg_command = [
        "jg",
        "-fpv",
        "-batch",
        "-tcl",
        tcl_file_path,
        "-define",
        "LM_ASSERT_TEXT",
        lm_assertion_text,
        "-define",
        "REF_ASSERT_TEXT",
        ref_assertion_text,
        "-define",
        "SIGNAL_LIST",
        signal_list_text,
        "-define",
        "EXP_ID",
        experiment_id,
        "-define",
        "TASK_ID",
        task_id,
        "-define",
        "SV_DIR",
        sv_dir,
        "-proj",
        tmp_jg_proj_dir,
        "-allow_unsupported_OS",
    ]
    # result = subprocess.run(jg_command, capture_output=True, text=True)

    FVEval_dir = os.path.abspath(os.path.join(os.path.dirname(tcl_file_path), '..'))

    result = subprocess.run(jg_command, cwd=FVEval_dir, capture_output=True, text=True)
    output_queue.put(result.stdout.strip())

import re

def calculate_coverage_metric(jasper_out_str):
    coverage_dict = {
        "stimuli_statement": 0.0,
        "stimuli_branch": 0.0,
        "stimuli_functional": 0.0,
        "stimuli_toggle": 0.0,
        "stimuli_expression": 0.0,
        "coi_statement": 0.0,
        "coi_branch": 0.0,
        "coi_functional": 0.0,
        "coi_toggle": 0.0,
        "coi_expression": 0.0,
    }

    # Extract coverage metrics
    coverage_matches = re.findall(r"(\w+)\|(\w+)\|(\d+\.\d+)", jasper_out_str)
    key_map = {
        ("coi", "statement"): "coi_statement",
        ("coi", "branch"): "coi_branch",
        ("coi", "functional"): "coi_functional",
        ("coi", "toggle"): "coi_toggle",
        ("coi", "expression"): "coi_expression",
        ("stimuli", "statement"): "stimuli_statement",
        ("stimuli", "branch"): "stimuli_branch",
        ("stimuli", "functional"): "stimuli_functional",
        ("stimuli", "toggle"): "stimuli_toggle",
        ("stimuli", "expression"): "stimuli_expression",
    }

    for category, model, value in coverage_matches:
        key = key_map.get((category, model))
        if key:
            coverage_dict[key] = float(value)

    # Initialize metric
    metric = {
        "syntax": 1.0,
        "functionality": 0.0,
        **{f"coverage_{k}": v for k, v in coverage_dict.items()}
    }

    # Check for syntax errors in the output
    if re.search(r"ERROR \(VERI-", jasper_out_str, re.IGNORECASE):
      metric["syntax"] = 0.0
      metric["functionality"] = 0.0
    # Search for proof results in the output

    if re.search(r"syntax error", jasper_out_str, re.IGNORECASE):
        metric["syntax"] = 0.0
        metric["functionality"] = 0.0
    # Search for proof results in the output
    proof_result_match = re.findall(r"\bproofs:[^\n]*", jasper_out_str)
    # coverage_result_match = re.findall(r"\bcoverage:[^\n]*", jasper_out_str)
    # print(f"Proof_result_match: {proof_result_match}")

    if not proof_result_match:
      metric["functionality"] = 0.0
      return metric
      
    proof_result_list = proof_result_match[-1].split(":")[-1].strip().split()
    # if coverage_result_match:
    # Proceed only if there's a match in coverage_result_match
      # coverage_result_list = coverage_result_match[-1].split(":")[-1].strip().split()

    # Count number of "proven" assertions
    if proof_result_list.count("proven") != 0:
      metric["functionality"] = 1.0

    # if FLAGS.both_cover_and_assertion:
    #   if coverage_result_match:
    #     if coverage_result_list.count("covered") == 0:
    #       metric["functionality"] = 0.0
    #   else:
    #     metric["functionality"] = 0.0

    return metric

    # # Check for syntax error
    # metric = {
    #         "syntax": 0.0,
    #         "functionality": 0.0,
    #         "func_relaxed": 0.0,
    #         "coverage": {}
    #     }
    # syntax_error_match = re.findall(r"syntax error", jasper_out_str, re.IGNORECASE)
    # if syntax_error_match:
    #     # Return zeros for all metrics if there's a syntax error
    #     return {
    #         "syntax": 0.0,
    #         "functionality": 0.0,
    #         "func_relaxed": 0.0,
    #         "coverage": {}
    #     }
    # syntax_score = 1.0

    # # Check for number of assertions proven
    # proof_result_match = re.findall(r"\bproofs:[^\n]*", jasper_out_str)
    # if not proof_result_match:
    #     # Return zeros for functionality if no proofs are found
    #     return {
    #         "syntax": syntax_score,
    #         "functionality": 0.0,
    #         "func_relaxed": 0.0,
    #         "coverage": {}
    #     }
    # proof_result_list = proof_result_match[-1].split(":")[-1].strip().split()
    # total_assertions = len(proof_result_list)
    # num_proven = proof_result_list.count("proven")
    # functionality_score = float(num_proven) / float(total_assertions)
    # num_undetermined = proof_result_list.count("undetermined")
    # relaxed_functionality_score = (num_proven + num_undetermined) / float(total_assertions)

    # # If functionality is zero, set all coverage metrics to zero
    # if functionality_score ==  1.0:
    #     # Set all coverage metrics to zero if no assertions are proven
    #     coverage_data = {}
    #     coverage_models = {
    #         'stimuli': ['functional', 'statement', 'toggle', 'expression', 'branch'],
    #         'coi': ['functional', 'statement', 'toggle', 'expression', 'branch']
    #     }
    #     for type_, models in coverage_models.items():
    #         coverage_data[type_] = {}
    #         for model in models:
    #             coverage_data[type_][model] = 0.0
    #     # return {
    #     #     "syntax": syntax_score,
    #     #     "functionality": functionality_score,
    #     #     "func_relaxed": relaxed_functionality_score,
    #     #     "coverage": coverage_data
    #     # }

    # # Extract coverage data
    # coverage_data = {}

    # # Adjusted regex pattern to match "TYPE|MODEL|COVERAGE"
    # coverage_pattern = r"(\w+)\|(\w+)\|([0-9.]+)"
    # coverage_matches = re.findall(coverage_pattern, jasper_out_str)

    # for type_, model, coverage_percent in coverage_matches:
    #     coverage_percent = float(coverage_percent)

    #     # Initialize the type dictionary if not already present
    #     if type_ not in coverage_data:
    #         coverage_data[type_] = {}

    #     # Since we don't have covered_items and total_items, we'll set them as None
    #     coverage_data[type_][model] = coverage_percent / 100.0  # Convert to a fraction


    # # Ensure that all expected combinations are included, even if missing from the output
    # coverage_models = {
    #     'stimuli': ['functional', 'statement', 'toggle', 'expression', 'branch'],
    #     'coi': ['functional', 'statement', 'toggle', 'expression', 'branch']
    # }
    # for type_, models in coverage_models.items():
    #     if type_ not in coverage_data:
    #         coverage_data[type_] = {}
    #     for model in models:
    #         if model not in coverage_data[type_]:
    #             # Set coverage to zero for missing combinations
    #             coverage_data[type_][model] = 0.0

    # return {
    #     "syntax": syntax_score,
    #     "functionality": functionality_score,
    #     "func_relaxed": relaxed_functionality_score,
    #     "coverage": coverage_data
    # }

def calculate_error_metric(jasper_out_str):
    # Initialize result dictionary with default values
    metric = {
        "syntax": 1.0,
        "functionality": 0.0
    }
    # Check for syntax errors in the output
    if re.search(r"ERROR \(VERI-", jasper_out_str, re.IGNORECASE):
      metric["syntax"] = 0.0
      metric["functionality"] = 0.0
    if re.search(r"syntax error", jasper_out_str, re.IGNORECASE):
      metric["syntax"] = 0.0
      metric["functionality"] = 0.0
    # Search for proof results in the output
    proof_result_match = re.findall(r"\bproofs:[^\n]*", jasper_out_str)
    coverage_result_match = re.findall(r"\bcoverage:[^\n]*", jasper_out_str)
    # print(f"Proof_result_match: {proof_result_match}")

    if not proof_result_match:
      metric["functionality"] = 0.0
      return metric
      
    proof_result_list = proof_result_match[-1].split(":")[-1].strip().split()
    if coverage_result_match:
    # Proceed only if there's a match in coverage_result_match
      coverage_result_list = coverage_result_match[-1].split(":")[-1].strip().split()

    # Count number of "proven" assertions
    if proof_result_list.count("proven") != 0:
      metric["functionality"] = 1.0

    if FLAGS.both_cover_and_assertion:
      if coverage_result_match:
        if coverage_result_list.count("covered") == 0:
          metric["functionality"] = 0.0
      else:
        metric["functionality"] = 0.0
    
    return metric

def calculate_RAG(jasper_out_str: str, design_code: str = None) -> Dict:
    """
    Calculate RAG (Red/Amber/Green) status and coverage details from Jasper output.
    Also saves the results to disk in a structured format.
    
    Args:
        jasper_out_str (str): The Jasper output string containing coverage information
        design_code (str, optional): The design code content for source code extraction
        
    Returns:
        dict: A dictionary containing:
            - Basic metrics (syntax, functionality)
            - Coverage summary statistics 
            - Detailed coverage information in a flat structure
    """
    # Get base metrics first
    result = calculate_coverage_metric(jasper_out_str)
    
    # Get detailed coverage analysis 
    if result['syntax'] == 1.0 and result['functionality'] == 1.0:
      coverage_details = analyze_uncovered_lines(
          jasper_out_str,
          design_code
      )
      # Calculate summary statistics
      coverage_summary = {
          'total_items': len(coverage_details),
          'by_type': {
              'undetectable': sum(1 for item in coverage_details.values() if item['type'] == 'undetectable'),
              'unprocessed': sum(1 for item in coverage_details.values() if item['type'] == 'unprocessed')
          },
          'by_status': {
              'unreachable': sum(
                  1 for item in coverage_details.values() 
                  if 'Unreachable' in item.get('formal_status', '')
              ),
              'undetectable': sum(
                  1 for item in coverage_details.values()
                  if 'Undetectable' in item.get('formal_status', '')
              )
          }
      }
    else:
      coverage_details = None
      coverage_summary = None

    # Combine all information
    full_results = {
        'metrics': result,
        'coverage_summary': coverage_summary,
        'coverage_details': coverage_details
    }
    
    return full_results
  
def check_single_assertion_error(design_rtl, packaged_tb_text, exp_id, task_id, index, temp_dir, tcl_check_path, iteration, signal, task, cleanup_temp_files, whole_batch):

    # SEQ_ID corresponds to 'index'; ITER_ID corresponds to 'iteration'
    seq_id = index
    iter_id = iteration

    # Create unique filenames for the testbench file
    folder_filename = f"{exp_id}_{task_id}_{iter_id}_{signal}_{seq_id}"
    sv_dir = os.path.join(temp_dir, folder_filename)
    os.makedirs(sv_dir, exist_ok=True)

    # testbench_filename = f"{exp_id}_{task_id}_{iter_id}_{seq_id}.sva"
    testbench_filename = f"{exp_id}_{task_id}.sva"
    testbench_file = os.path.join(temp_dir, folder_filename, testbench_filename)
    design_filename = f"{task}_{task_id}.sv"
    design_file = os.path.join(temp_dir, folder_filename, design_filename)

    with open(testbench_file, "w") as f:
      f.write(packaged_tb_text)
    with open(design_file, "w") as f:
      f.write(design_rtl)
    if task_id == "omsp_frontend":
      omsp_clock_gate_file = os.path.join(sv_dir, 'omsp_clock_gate.v')
      with open(omsp_clock_gate_file, "w") as f:
          f.write(omsp_clock_gate)
      omsp_and_gate_file = os.path.join(sv_dir, 'omsp_and_gate.v')
      with open(omsp_and_gate_file, "w") as f:
          f.write(omsp_and_gate)
    # if exp_id == "design2sva_training_docs" and task_id == "top":
    #     arbiter_design_file = os.path.join(sv_dir, 'arbiter.v')
    #     with open(arbiter_design_file, "w") as f:
    #         f.write(arbiter_v)
    #     arbiter_design_file = os.path.join(sv_dir, 'fifo.v')
    #     with open(arbiter_design_file, "w") as f:
    #         f.write(fifo_v)

    # The design file should already exist

    jg_start_time = time.time()

    # Launch JasperGold and get the output directly
    if task in ["design2sva_fsm", "design2sva_pipeline", "design2sva_training_docs"]:
      jasper_output = launch_jg(
        tcl_file_path=tcl_check_path,
        sv_dir=sv_dir,
        experiment_id=exp_id,
        task_id=task_id,
        iter_id=iter_id,
        seq_id=seq_id
      )

    elif task in ["design2sva_assertionbench"]:
      jasper_output = launch_jg(
        tcl_file_path=tcl_check_path,
        sv_dir=sv_dir,
        experiment_id=exp_id,
        task_id=task_id,
        iter_id=iter_id,
        seq_id=seq_id,
        CLK = task_signals[task_id]["clock"],
        RST = task_signals[task_id]["reset"],
        TOP = task_signals[task_id]["top"],
      )

    jg_execution_time = time.time() - jg_start_time

    if cleanup_temp_files:
      shutil.rmtree(sv_dir)

    # print(f"JapserGold Output[{exp_id}_{task_id}_{iter_id}_{seq_id}]:{jasper_output}")

    # Clean up temporary files if necessary

    # Process the output and return results
    # print(f"JasperGold Output: {jasper_output}")
    if FLAGS.use_ICRL:
      metrics = calculate_RAG(jasper_output, design_rtl)
      syntax = metrics["metrics"]["syntax"]
      functionality = metrics["metrics"]["functionality"]
    else:
      metrics = calculate_error_metric(jasper_output)
      syntax = metrics["syntax"]
      functionality = metrics["functionality"]

    # Save timing stats for successful runs
    if FLAGS.use_ICRL:
      if syntax == 1.0 and functionality == 1.0 and whole_batch == False:
        stats_key = f"jasper_syntax_coverage_time"
        saver.save_stats(stats_key, jg_execution_time) 
      elif whole_batch == False:
        stats_key = f"jasper_syntax_time"
        saver.save_stats(stats_key, jg_execution_time)
      elif whole_batch == True:
        stats_key = f"jasper_batch_coverage_time"
        saver.save_stats(stats_key, jg_execution_time)
    else:
      stats_key = f"jasper_syntax_time"
      saver.save_stats(stats_key, jg_execution_time)

    print(f"error_metrics[{exp_id}_{task_id}_{iter_id}_{seq_id}]: syntax: {syntax}, functionality: {functionality}")

    is_valid = syntax == 1.0 and functionality == 1.0
    # print(f"is_valid: {is_valid}")
    return is_valid, jasper_output, metrics

def worker(exp_id, task_id, i, temp_dir, tcl_check_path, iteration, design_rtl, packaged_tb_text, output_queue, task):
    folder_filename = f"{exp_id}_{task_id}_{str(iteration)}_{str(i)}"
    sv_dir = os.path.join(temp_dir, folder_filename)
    os.makedirs(sv_dir, exist_ok=True)

    testbench_filename = f"{exp_id}_{task_id}_{str(iteration)}_{str(i)}.sva"
    testbench_file = os.path.join(temp_dir, folder_filename, testbench_filename)
    design_filename = f"{task}_{task_id}.sv"
    design_file = os.path.join(temp_dir, folder_filename, design_filename)

    with open(testbench_file, "w") as f:
        f.write(packaged_tb_text)
    with open(design_file, "w") as f:
        f.write(design_rtl)
    # if exp_id == "design2sva_training_docs" and task_id == "top":
    #     arbiter_design_file = os.path.join(sv_dir, 'arbiter.v')
    #     with open(arbiter_design_file, "w") as f:
    #         f.write(arbiter_v)
    #     arbiter_design_file = os.path.join(sv_dir, 'fifo.v')
    #     with open(arbiter_design_file, "w") as f:
    #         f.write(fifo_v)

    # Now, launch the JasperGold process
    launch_jg_with_queue(
        tcl_file_path=tcl_check_path,
        sv_dir=sv_dir,
        experiment_id=exp_id,
        task_id=task_id,
        iter_id=str(iteration),
        seq_id=str(i),
        output_queue=output_queue,
    )

def check_assertions_error_parallel(
    design_rtl: str,
    packaged_tb_texts: List[str],
    exp_id: str,
    task_id: str,
    temp_dir: str,
    tcl_check_path: str,
    num_processes: int,
    iteration: int,
    signal: str,
    task: str,
    cleanup_temp_files: bool,
) -> List[Tuple[bool, str]]:
    output_queue = multiprocessing.Queue()
    results = []

    if num_processes == 1:
        # Sequential execution
        for i, tb_text in enumerate(packaged_tb_texts):
          result = check_single_assertion_error(
            design_rtl, tb_text, exp_id, task_id, str(i), temp_dir, tcl_check_path, str(iteration), signal, task, cleanup_temp_files, whole_batch = False
          )
          results.append(result)
    else:
        # Parallel execution using multiprocessing
        processes = []
        for i, tb_text in enumerate(packaged_tb_texts):
            p = multiprocessing.Process(
                target=worker,
                args=(exp_id, task_id, i, temp_dir, tcl_check_path, iteration, design_rtl, tb_text, output_queue, task)
            )
            processes.append(p)
            p.start()

        # Wait for all processes to complete
        for p in processes:
            p.join()

        # Collect results from the queue
        results_dict = {}
        while not output_queue.empty():
            seq_id, jasper_output = output_queue.get()
            # print(f"JasperGold Output[{exp_id}_{task_id}_{iteration}_{seq_id}]:{jasper_output}")
            # Process the output and return results
            error_metrics = calculate_error_metric(jasper_output)
            print(f"error_metrics[{exp_id}_{task_id}_{iteration}_{seq_id}]:{error_metrics}")
            is_valid = error_metrics["syntax"] == 1.0 and error_metrics["functionality"] == 1.0
            results_dict[int(seq_id)] = (is_valid, jasper_output)

        # Reconstruct results in the original order
        results = [results_dict[i] for i in range(len(packaged_tb_texts))]

    return results

def check_assertions_report_parallel(
    design_rtl: str,
    packaged_tb_texts: List[str],
    exp_id: str,
    task_id: str,
    temp_dir: str,
    tcl_check_path: str,
    num_processes: int,
    iteration: int,
    signal: str,
    task: str,
    cleanup_temp_files: bool,
    whole_batch = True,
) -> List[Tuple[bool, str, Dict]]:
    """Modified to return metrics with each result"""
    output_queue = multiprocessing.Queue()
    results = []

    if num_processes == 1:
        for i, tb_text in enumerate(packaged_tb_texts):
            result = check_single_assertion_error(
                design_rtl, tb_text, exp_id, task_id, str(i), temp_dir, 
                tcl_check_path, str(iteration), signal, task, cleanup_temp_files, whole_batch
            )
            results.append(result)
    else:
        processes = []
        for i, tb_text in enumerate(packaged_tb_texts):
            p = multiprocessing.Process(
                target=worker,
                args=(exp_id, task_id, i, temp_dir, tcl_check_path, iteration, 
                      design_rtl, tb_text, output_queue, task)
            )
            processes.append(p)
            p.start()

        for p in processes:
            p.join()

        results_dict = {}
        while not output_queue.empty():
            seq_id, jasper_output = output_queue.get()
            if FLAGS.use_ICRL:
                metrics = calculate_RAG(jasper_output, design_rtl)
                syntax = metrics["metrics"]["syntax"]
                functionality = metrics["metrics"]["functionality"]
            else:
                metrics = calculate_error_metric(jasper_output)
                syntax = metrics["syntax"]
                functionality = metrics["functionality"]
            
            is_valid = syntax == 1.0 and functionality == 1.0
            results_dict[int(seq_id)] = (is_valid, jasper_output, metrics)

        results = [results_dict[i] for i in range(len(packaged_tb_texts))]

    return results

# jasper_output = analyze_coverage(row.prompt, packaged_combined_tb, FLAGS.task, row.task_id, temp_dir, FLAGS.tcl_report_path
def analyze_coverage(design_rtl: str, packaged_tb_text: str, exp_id: str, task_id: str, temp_dir: str, tcl_coverage_path: str, cleanup_temp_files: bool, tb_modul_str: str, iteration: int) -> Dict[str, float]:

    folder_filename = f"{exp_id}_{task_id}__{str(iteration)}"
    sv_dir = os.path.join(temp_dir, folder_filename)
    os.makedirs(sv_dir, exist_ok=True)
    testbench_filename = f"{exp_id}_{task_id}.sva"
    testbench_file = os.path.join(temp_dir, folder_filename, testbench_filename)
    design_filename = f"{exp_id}_{task_id}.sv"
    design_file = os.path.join(temp_dir, folder_filename, design_filename)

    with open(testbench_file, "w") as f:
      f.write(packaged_tb_text)
    with open(design_file, "w") as f:
      f.write(design_rtl)
    if task_id == "omsp_frontend":
      omsp_clock_gate_file = os.path.join(sv_dir, 'omsp_clock_gate.v')
      with open(omsp_clock_gate_file, "w") as f:
          f.write(omsp_clock_gate)
      omsp_and_gate_file = os.path.join(sv_dir, 'omsp_and_gate.v')
      with open(omsp_and_gate_file, "w") as f:
          f.write(omsp_and_gate)

    # Launch JasperGold using launch_jg
    if exp_id in ["design2sva_fsm", "design2sva_pipeline", "design2sva_training_docs"]:
        jasper_output = launch_jg(
            tcl_file_path=tcl_coverage_path,
            sv_dir=sv_dir,
            experiment_id=exp_id,
            task_id=task_id,
            TB_MODULE=tb_modul_str,
        )
    elif exp_id in ["design2sva_assertionbench"]:
        jasper_output = launch_jg(
            tcl_file_path=tcl_coverage_path,
            sv_dir=sv_dir,
            experiment_id=exp_id,
            task_id=task_id,
            CLK = task_signals[task_id]["clock"],
            RST = task_signals[task_id]["reset"],
            TB_MODULE=tb_modul_str,
            TOP = task_signals[task_id]["top"],
        )

    if cleanup_temp_files:
        shutil.rmtree(sv_dir)

    # Calculate coverage metrics using calculate_coverage_metric
    # print(f"JasperGold report for coverage: {jasper_output}")
    return jasper_output

def read_file(file_path: str) -> str:
    """
    Read the content of a file.

    :param file_path: Path to the file to be read.
    :return: Content of the file as a string. Returns an empty string if the file is not found.
    """
    try:
        with open(file_path, 'r') as f:
            return f.read()
    except FileNotFoundError:
        print(f"File not found: {file_path}")
        return None


def extract_and_parse_items(text):
    items = []
    stack = []
    current_item = ''
    inside_item = False
    for c in text:
        if c == '{':
            stack.append('{')
            current_item += c
            inside_item = True
        elif c == '}':
            stack.pop()
            current_item += c
            if not stack:
                items.append(current_item.strip())
                current_item = ''
                inside_item = False
        else:
            if inside_item:
                current_item += c
    return [parse_nested_dict(item) for item in items]


def parse_nested_dict(s):
    s = s.strip()
    if s.startswith('{') and s.endswith('}'):
        # Remove outer braces
        s = s[1:-1].strip()
        # If content does not contain inner braces, treat as string
        if '{' not in s and '}' not in s:
            return s
        else:
            # Content contains inner braces, attempt to parse as dict
            result = {}
            tokens = tokenize(s)
            i = 0
            while i < len(tokens):
                key = tokens[i]
                i += 1
                if i < len(tokens):
                    value = tokens[i]
                    i += 1
                    result[key] = parse_nested_dict(value)
                else:
                    result[key] = None
            return result
    else:
        # Not enclosed in braces, return as is
        return s


def extract_items(text):
    items = []
    stack = []
    current_item = ''
    for c in text:
        if c == '{':
            if not stack:
                current_item = ''
            stack.append('{')
            current_item += c
        elif c == '}':
            stack.pop()
            current_item += c
            if not stack:
                items.append(current_item)
        else:
            if stack:
                current_item += c
    return items

def tokenize(s):
    tokens = []
    i = 0
    n = len(s)
    while i < n:
        if s[i].isspace():
            i += 1
            continue
        elif s[i] == '{':
            # Parse nested braces
            start = i
            stack = ['{']
            i += 1
            while i < n and stack:
                if s[i] == '{':
                    stack.append('{')
                elif s[i] == '}':
                    stack.pop()
                i += 1
            tokens.append(s[start:i])
        else:
            # Parse until the next whitespace or brace
            start = i
            while i < n and not s[i].isspace() and s[i] != '{' and s[i] != '}':
                i += 1
            tokens.append(s[start:i])
    return tokens


def parse_item(s):
    s = s.strip()
    if s.startswith('{') and s.endswith('}'):
        s = s[1:-1].strip()
    d = {}
    tokens = tokenize(s)
    i = 0
    while i < len(tokens):
        key = tokens[i]
        i += 1
        if i < len(tokens):
            value = tokens[i]
            i += 1
            if value.startswith('{') and value.endswith('}'):
                value_content = value[1:-1].strip()
                d[key] = value_content
            else:
                d[key] = value
        else:
            d[key] = None
    return d

# def analyze_covered_lines(jasper_out_str):
#     # Define markers to extract the COI coverage report and detailed covered items report
#     START_MARKER = "### COVERED_ITEMS_REPORT_START ###"
#     END_MARKER = "### COVERED_ITEMS_REPORT_END ###"
#     SUMMARY_HEADER = "### COI COVERAGE REPORT ###"

#     # Locate the start and end of the report section for detailed covered items
#     start_idx = jasper_out_str.find(START_MARKER)
#     end_idx = jasper_out_str.find(END_MARKER)

#     if start_idx == -1 or end_idx == -1:
#         return {}

#     # Extract the coverage summary and detailed items text
#     summary_idx = jasper_out_str.find(SUMMARY_HEADER)
#     summary_text = jasper_out_str[summary_idx:start_idx].strip() if summary_idx != -1 else ""
#     covered_items_text = jasper_out_str[start_idx + len(START_MARKER):end_idx].strip()

#     # Parse the summary section to get counts of covered items by model
#     coverage_summary = {}
#     for line in summary_text.splitlines():
#         if "|" in line:  # Skip header and separator lines
#             model, covered_count = line.split("|")
#             coverage_summary[model.strip()] = int(covered_count.strip())

#     # Parse the detailed covered items section
#     detailed_coverage = {}
#     current_model = None
#     for line in covered_items_text.splitlines():
#         line = line.strip()
#         if line.startswith("COI - Covered items for"):
#             # Extract the model name
#             current_model = line.split("for")[-1].strip().lower()
#             detailed_coverage[current_model] = []
#         elif current_model and line:
#             # Split the line by commas to get individual items and add them to the model's list
#             items = [item.strip() for item in line.split(",")]
#             detailed_coverage[current_model].extend(items)

#     # Return a dictionary containing both the summary and detailed coverage information
#     return {
#         "coverage_summary": coverage_summary,
#         "detailed_coverage": detailed_coverage
#     }

def analyze_uncovered_lines(jasper_out_str, design_code, coverage_types=None):
    """
    Analyze uncovered lines from Jasper output and return a flat structured dictionary.
    
    Args:
        jasper_out_str (str): The Jasper output string containing coverage information
        design_code (str): The design code content
        coverage_types (list): List containing "undetectable" and/or "unprocessed" to filter results
                             If None, both types will be included
    
    Returns:
        dict: A flat dictionary containing all coverage items:
        {
            'id_hash': {
                'type': 'undetectable',  # or 'unprocessed'
                'expression': str,
                'formal_status': str,
                'stimuli_status': str,
                'checker_status': str,
                'cover_item_type': str,
                'bound': str,
                'description': str,
                'source_code': str,
                'source_location': str
            },
            ...
        }
    """
    coverage_types = FLAGS.coverage_types
    START_MARKER = "### COVERAGE_REPORT_START ###"
    END_MARKER = "### COVERAGE_REPORT_END ###"
    
    # Initialize result dictionary
    result = {}
    
    # Validate coverage_types parameter
    valid_types = ["undetectable", "unprocessed"]
    if coverage_types is not None:
        coverage_types = [ct.lower() for ct in coverage_types]
        if not all(ct in valid_types for ct in coverage_types):
            raise ValueError(f"coverage_types must be a list containing only: {valid_types}")
    else:
        coverage_types = valid_types

    first_start = jasper_out_str.find(START_MARKER)
    start_idx = jasper_out_str.find(START_MARKER, first_start + 1)

    # Similarly for END_MARKER:
    first_end = jasper_out_str.find(END_MARKER, first_start)
    end_idx = jasper_out_str.find(END_MARKER, start_idx)

    if start_idx == -1 or end_idx == -1:
        return result

    coverage_text = jasper_out_str[start_idx + len(START_MARKER):end_idx].strip()

    # Extract texts based on coverage types
    texts = {
        'undetectable': "",
        'unprocessed': ""
    }
    
    if "undetectable" in coverage_types:
        undetectable_start = coverage_text.find("### UNDETECTABLE_START ###")
        if undetectable_start != -1:
            undetectable_end = coverage_text.find("### UNDETECTABLE_END ###")
            if undetectable_end == -1:
                undetectable_end = len(coverage_text)
            texts['undetectable'] = coverage_text[undetectable_start:undetectable_end].strip()
            # print(f"texts['undetectable']: {texts['undetectable']}")

    if "unprocessed" in coverage_types:
        unprocessed_start = coverage_text.find("### UNPROCESSED_START ###")
        if unprocessed_start != -1:
            texts['unprocessed'] = coverage_text[unprocessed_start:].strip()

    # Process items for each requested coverage type
    for coverage_type in coverage_types:
        items = extract_and_parse_items(texts[coverage_type])
        
        # Extract source code snippets for all items
        source_locations = [item.get('source_location') for item in items if isinstance(item, dict) and 'source_location' in item]
        code_snippets = extract_source_code_snippets(source_locations, design_code)
        
        # Process each item
        for item in items:
            if not isinstance(item, dict):
                continue
                
            formal_status = item.get('formal_status', '')
            if 'Unreachable' in formal_status or 'Undetectable' in formal_status:
                # Create a unique hash using relevant item fields
                hash_fields = []
                for key in sorted(item.keys()):
                    value = item.get(key, '')
                    if isinstance(value, (str, int, float, bool)):
                        hash_fields.append(f"{key}:{value}")
                
                # Create a unique identifier string and hash it
                identifier = "|".join(hash_fields)
                item_hash = hash(identifier)
                
                # Create cleaned item dictionary with only desired fields
                cleaned_item = {
                    'type': coverage_type,  # Add type information to each item
                    **{key: item.get(key, '')
                       for key in ['expression', 'formal_status', 'stimuli_status', 
                                 'checker_status', 'cover_item_type', 'bound', 'description','cid']}
                }
                
                # Add source code if available
                if 'source_location' in item:
                    cleaned_item['source_location'] = item['source_location']
                    cleaned_item['source_code'] = code_snippets.get(item['source_location'], '')
                
                # Add to result dictionary
                result[item_hash] = cleaned_item

    return result

def compare_coverage_reports(old_report, new_report):
    """
    Compare two coverage reports and identify added and removed items.
    
    Args:
        old_report (dict): Previous coverage report
        new_report (dict): Current coverage report
    
    Returns:
        dict: Changes between reports:
        {
            'added': [items],
            'removed': [items],
            'summary_changes': {
                'total_change': int,
                'by_type': {'undetectable': int, 'unprocessed': int},
                'by_status': {'unreachable': int, 'undetectable': int}
            }
        }
    """
    old_items = set(old_report.keys())
    new_items = set(new_report.keys())
    
    # Find added and removed items
    added_hashes = new_items - old_items
    removed_hashes = old_items - new_items
    
    # Calculate summary changes
    summary_changes = {
        'total_change': len(new_items) - len(old_items),
        'by_type': {
            'undetectable': (
                sum(1 for item in new_report.values() if item['type'] == 'undetectable') -
                sum(1 for item in old_report.values() if item['type'] == 'undetectable')
            ),
            'unprocessed': (
                sum(1 for item in new_report.values() if item['type'] == 'unprocessed') -
                sum(1 for item in old_report.values() if item['type'] == 'unprocessed')
            )
        },
        'by_status': {
            'unreachable': (
                sum(1 for item in new_report.values() if 'Unreachable' in item.get('formal_status', '')) -
                sum(1 for item in old_report.values() if 'Unreachable' in item.get('formal_status', ''))
            ),
            'undetectable': (
                sum(1 for item in new_report.values() if 'Undetectable' in item.get('formal_status', '')) -
                sum(1 for item in old_report.values() if 'Undetectable' in item.get('formal_status', ''))
            )
        }
    }
    
    return {
        'added': [new_report[item_hash] for item_hash in added_hashes],
        'removed': [old_report[item_hash] for item_hash in removed_hashes],
        'summary_changes': summary_changes
    }

def extract_source_code_snippets(source_locations: List[str], design_code: str) -> Dict[str, str]:
    """
    Extract code snippets based on source locations in the design code.

    Args:
        source_locations (List[str]): List of source locations, each in the format "(line_start,col_start)-(line_end,col_end)".
        design_code (str): The full source code of the design.

    Returns:
        Dict[str, str]: A dictionary mapping source location strings to the extracted code snippets.
    """
    # Split the design code into individual lines
    design_lines = design_code.splitlines()

    extracted_snippets = {}

    for location in source_locations:
        try:
            # Extract the start and end line/column information
            start, end = location.split("-")
            line_start, col_start = map(int, start.strip("()").split(","))
            line_end, col_end = map(int, end.strip("()").split(","))

            # Extract the code snippet based on the line and column information
            if line_start == line_end:
                snippet = design_lines[line_start - 1][col_start - 1:col_end]
            else:
                snippet_lines = [
                    design_lines[line_start - 1][col_start - 1:]
                ]
                snippet_lines.extend(design_lines[line_start:line_end - 1])
                snippet_lines.append(design_lines[line_end - 1][:col_end])
                snippet = "\n".join(snippet_lines)

            # Add the extracted snippet to the result dictionary
            extracted_snippets[location] = snippet
        except (IndexError, ValueError) as e:
            # Handle any errors that may arise from invalid locations or design code issues
            extracted_snippets[location] = f"Error extracting snippet: {e}"

    return extracted_snippets

def format_newly_covered_items(coverage_info: dict) -> str:
    """
    Format uncovered items and coverage information into a readable string.
    
    Args:
        coverage_info: Dictionary containing coverage information with structure:
            {
                'newly_covered_holes': Dict of newly covered items,
                'metrics': Coverage metrics,
                'coverage_details': Detailed coverage information
            }
            
    Returns:
        Formatted string with coverage information
    """
    formatted_parts = []
    
    # Add coverage metrics summary if available
    metrics = coverage_info.get('metrics', {})
    if metrics:
        formatted_parts.append("Coverage Metrics:")
        for model in ['statement', 'branch', 'functional', 'toggle', 'expression']:
            coi_value = metrics.get(f'coverage_coi_{model}', 0)
            if coi_value > 0:
                formatted_parts.append(f"- COI {model.capitalize()}: {coi_value:.1f}%")
    
    # Format newly covered holes
    newly_covered = coverage_info.get('newly_covered_holes', {})
    if newly_covered:
        formatted_parts.append(f"\nNewly Covered Items ({len(newly_covered)}):")
        for item_hash, item_info in newly_covered.items():
            # Extract key information from the coverage item
            expression = item_info.get('expression', 'N/A')
            source_code = item_info.get('source_code', 'N/A')
            source_location = item_info.get('source_location', 'N/A')
            coverage_type = item_info.get('cover_item_type', 'N/A')
            
            formatted_parts.append(
                f"- Item Type: {coverage_type}\n"
                f"  Expression: {expression}\n"
                f"  Source Code: {source_code}\n"
                # f"  Location: {source_location}"
            )
    
    return "\n".join(formatted_parts)

def format_assertion_collection(assertions_info: list) -> str:
    """
    Format a collection of assertions with their coverage information.
    
    Args:
        assertions_info: List of dictionaries containing assertion information:
            [{
                'index': assertion index,
                'assertion': assertion code,
                'coverage_info': coverage information dict
            }]
            
    Returns:
        Formatted string containing all assertions and their coverage details
    """
    formatted_sections = []
    
    for info in assertions_info:
        section = [f"Assertion {info['index']}:\n"]
        section.append(f"```systemverilog\n{info['assertion']}\n```\n")
        
        # Add coverage information
        coverage_text = format_newly_covered_items(info['coverage_info'])
        if coverage_text:
            section.append(coverage_text)
            
        formatted_sections.append("\n".join(section))
    
    return "\n\n".join(formatted_sections)

def format_uncovered_items(data, sample_size=10):
    formatted_data = []
    
    # Handle cases where uncovered holes are less than the sample size
    sampled_items = random.sample(list(data.items()), min(sample_size, len(data)))
    
    for index, (key, entry) in enumerate(sampled_items, start=1):
        formatted_entry = (
            f"ID: {index}\n"
            f"Type: {entry['type']}\n"
            f"Expression: {entry['expression']}\n"
            f"Formal Status: {entry['formal_status']}\n"
            f"Cover Item Type: {entry['cover_item_type']}\n"
            f"Description: {entry['description']}\n"
            f"Source Location: {entry['source_location']}\n"
            f"Source Code: {entry['source_code']}\n"
            f"{'-'*40}\n"
        )
        formatted_data.append(formatted_entry)
    
    return "\n".join(formatted_data)
    

def remove_comments(code: str) -> str:
    """
    Remove all comments from the given code string.

    Args:
        code (str): The code string from which to remove comments.

    Returns:
        str: The code string with comments removed.
    """
    # Remove single-line comments (//...)
    code_no_single_comments = re.sub(r'//.*', '', code)
    # Remove block comments (/*...*/)
    code_no_comments = re.sub(r'/\*.*?\*/', '', code_no_single_comments, flags=re.DOTALL)
    return code_no_comments.strip()

task_signals = {
    "apb": {"clock": "PCLK", "reset": "PRESETn", "top":"apb"},
    "module_i2c": {"clock": "PCLK", "reset": "PRESETn", "top":"module_i2c"},
    "counter": {"clock": "clk", "reset": "reset", "top":"counter"},
    "rxLenTypChecker": {"clock": "rxclk", "reset": "reset", "top":"rxLenTypChecker"},
    "rxStatModule": {"clock": "rxclk", "reset": "reset", "top":"rxStatModule"},
    "rxLinkFaultState": {"clock": "rxclk", "reset": "reset", "top":"rxLinkFaultState"},
    "ack_counter": {"clock": "clock", "reset": "reset", "top":"ack_counter"},
    "eth_transmitcontrol": {"clock": "MTxClk", "reset": "TxReset", "top":"eth_transmitcontrol"},
    "eth_rxethmac": {"clock": "MRxClk", "reset": "Reset", "top":"eth_rxethmac"},
    "MAC_rx_FF": {"clock": "Clk_MAC", "reset": "Reset", "top":"MAC_rx_FF"},
    "eth_cop": {"clock": "wb_clk_i", "reset": "wb_rst_i", "top":"eth_cop"},
    "eth_macstatus": {"clock": "MRxClk", "reset": "Reset", "top":"eth_macstatus"},
    "ge_1000baseX_rx": {"clock": "ck", "reset": "reset", "top":"ge_1000baseX_rx"},
    "ge_1000baseX_sync": {"clock": "ck", "reset": "reset", "top":"ge_1000baseX_sync"},
    "omsp_frontend": {"clock": "mclk", "reset": "puc_rst", "top": "omsp_frontend"},
    "fht_1d_x8": {"clock": "sclk", "reset": "rstn", "top": "fht_1d_x8"},
    "control_unit": {"clock": "clk", "reset": "rst_n", "top": "control_unit"},
    "uartRec": {"clock": "clk", "reset": "reset", "top": "uartRec"},
    "host_interface": {"clock": "-infer", "reset": "-none", "top": "host_interface"},
    "fpu_exceptions": {"clock": "clk", "reset": "rst", "top": "fpu_exceptions"},
    "MAC_rx_ctrl": {"clock": "Clk", "reset": "Reset", "top": "MAC_rx_ctrl"},
    "cavlc_read_levels": {"clock": "Clk", "reset": "Reset", "top": "cavlc_read_levels"},
    "can_fifo": {"clock": "clk", "reset": "rst", "top": "can_fifo"},
    "PSGBusArb": {"clock": "clk", "reset": "rst", "top": "PSGBusArb"},
    # Add more task_ids as needed
}

eth_rxethmac = """
/////////////////////////////////////////////////////////////////////
////                                                              ////
////  eth_rxethmac.v                                              ////
////                                                              ////
////  This file is part of the Ethernet IP core project           ////
////  http://www.opencores.org/project,ethmac                     ////
////                                                              ////
////  Author(s):                                                  ////
////      - Igor Mohor (igorM@opencores.org)                      ////
////      - Novan Hartadi (novan@vlsi.itb.ac.id)                  ////
////      - Mahmud Galela (mgalela@vlsi.itb.ac.id)                ////
////      - Olof Kindgren (olof@opencores.org                     ////
////                                                              ////
////  All additional information is avaliable in the Readme.txt   ////
////  file.                                                       ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
////                                                              ////
//// Copyright (C) 2001, 2011 Authors                             ////
////                                                              ////
//// This source file may be used and distributed without         ////
//// restriction provided that this copyright statement is not    ////
//// removed from the file and that any derivative work contains  ////
//// the original copyright notice and the associated disclaimer. ////
////                                                              ////
//// This source file is free software; you can redistribute it   ////
//// and/or modify it under the terms of the GNU Lesser General   ////
//// Public License as published by the Free Software Foundation; ////
//// either version 2.1 of the License, or (at your option) any   ////
//// later version.                                               ////
////                                                              ////
//// This source is distributed in the hope that it will be       ////
//// useful, but WITHOUT ANY WARRANTY; without even the implied   ////
//// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      ////
//// PURPOSE.  See the GNU Lesser General Public License for more ////
//// details.                                                     ////
////                                                              ////
//// You should have received a copy of the GNU Lesser General    ////
//// Public License along with this source; if not, download it   ////
//// from http://www.opencores.org/lgpl.shtml                     ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
//
// 2011-07-06 Olof Kindgren <olof@opencores.org>
// Add ByteCntEq0 to rxaddrcheck
//
// CVS Revision History
//
//
// $Log: not supported by cvs2svn $
// Revision 1.12  2004/04/26 15:26:23  igorm
// - Bug connected to the TX_BD_NUM_Wr signal fixed (bug came in with the
//   previous update of the core.
// - TxBDAddress is set to 0 after the TX is enabled in the MODER register.
// - RxBDAddress is set to r_TxBDNum<<1 after the RX is enabled in the MODER
//   register. (thanks to Mathias and Torbjorn)
// - Multicast reception was fixed. Thanks to Ulrich Gries
//
// Revision 1.11  2004/03/17 09:32:15  igorm
// Multicast detection fixed. Only the LSB of the first byte is checked.
//
// Revision 1.10  2002/11/22 01:57:06  mohor
// Rx Flow control fixed. CF flag added to the RX buffer descriptor. RxAbort
// synchronized.
//
// Revision 1.9  2002/11/19 17:35:35  mohor
// AddressMiss status is connecting to the Rx BD. AddressMiss is identifying
// that a frame was received because of the promiscous mode.
//
// Revision 1.8  2002/02/16 07:15:27  mohor
// Testbench fixed, code simplified, unused signals removed.
//
// Revision 1.7  2002/02/15 13:44:28  mohor
// RxAbort is an output. No need to have is declared as wire.
//
// Revision 1.6  2002/02/15 11:17:48  mohor
// File format changed.
//
// Revision 1.5  2002/02/14 20:48:43  billditt
// Addition  of new module eth_addrcheck.v
//
// Revision 1.4  2002/01/23 10:28:16  mohor
// Link in the header changed.
//
// Revision 1.3  2001/10/19 08:43:51  mohor
// eth_timescale.v changed to timescale.v This is done because of the
// simulation of the few cores in a one joined project.
//
// Revision 1.2  2001/09/11 14:17:00  mohor
// Few little NCSIM warnings fixed.
//
// Revision 1.1  2001/08/06 14:44:29  mohor
// A define FPGA added to select between Artisan RAM (for ASIC) and Block Ram (For Virtex).
// Include files fixed to contain no path.
// File names and module names changed ta have a eth_ prologue in the name.
// File eth_timescale.v is used to define timescale
// All pin names on the top module are changed to contain _I, _O or _OE at the end.
// Bidirectional signal MDIO is changed to three signals (Mdc_O, Mdi_I, Mdo_O
// and Mdo_OE. The bidirectional signal must be created on the top level. This
// is done due to the ASIC tools.
//
// Revision 1.1  2001/07/30 21:23:42  mohor
// Directory structure changed. Files checked and joind together.
//
// Revision 1.1  2001/06/27 21:26:19  mohor
// Initial release of the RxEthMAC module.
//
//
//
//
//

`timescale 1ns / 1ns

//////////////////////////////////////////////////////////////////////
////                                                              ////
////  eth_crc.v                                                   ////
////                                                              ////
////  This file is part of the Ethernet IP core project           ////
////  http://www.opencores.org/project,ethmac                     ////
////                                                              ////
////  Author(s):                                                  ////
////      - Igor Mohor (igorM@opencores.org)                      ////
////      - Novan Hartadi (novan@vlsi.itb.ac.id)                  ////
////      - Mahmud Galela (mgalela@vlsi.itb.ac.id)                ////
////                                                              ////
////  All additional information is avaliable in the Readme.txt   ////
////  file.                                                       ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
////                                                              ////
//// Copyright (C) 2001 Authors                                   ////
////                                                              ////
//// This source file may be used and distributed without         ////
//// restriction provided that this copyright statement is not    ////
//// removed from the file and that any derivative work contains  ////
//// the original copyright notice and the associated disclaimer. ////
////                                                              ////
//// This source file is free software; you can redistribute it   ////
//// and/or modify it under the terms of the GNU Lesser General   ////
//// Public License as published by the Free Software Foundation; ////
//// either version 2.1 of the License, or (at your option) any   ////
//// later version.                                               ////
////                                                              ////
//// This source is distributed in the hope that it will be       ////
//// useful, but WITHOUT ANY WARRANTY; without even the implied   ////
//// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      ////
//// PURPOSE.  See the GNU Lesser General Public License for more ////
//// details.                                                     ////
////                                                              ////
//// You should have received a copy of the GNU Lesser General    ////
//// Public License along with this source; if not, download it   ////
//// from http://www.opencores.org/lgpl.shtml                     ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
//
// CVS Revision History
//
// $Log: not supported by cvs2svn $
// Revision 1.2  2001/10/19 08:43:51  mohor
// eth_timescale.v changed to timescale.v This is done because of the
// simulation of the few cores in a one joined project.
//
// Revision 1.1  2001/08/06 14:44:29  mohor
// A define FPGA added to select between Artisan RAM (for ASIC) and Block Ram (For Virtex).
// Include files fixed to contain no path.
// File names and module names changed ta have a eth_ prologue in the name.
// File eth_timescale.v is used to define timescale
// All pin names on the top module are changed to contain _I, _O or _OE at the end.
// Bidirectional signal MDIO is changed to three signals (Mdc_O, Mdi_I, Mdo_O
// and Mdo_OE. The bidirectional signal must be created on the top level. This
// is done due to the ASIC tools.
//
// Revision 1.1  2001/07/30 21:23:42  mohor
// Directory structure changed. Files checked and joind together.
//
// Revision 1.3  2001/06/19 18:16:40  mohor
// TxClk changed to MTxClk (as discribed in the documentation).
// Crc changed so only one file can be used instead of two.
//
// Revision 1.2  2001/06/19 10:38:07  mohor
// Minor changes in header.
//
// Revision 1.1  2001/06/19 10:27:57  mohor
// TxEthMAC initial release.
//
//
//



module eth_crc (Clk, Reset, Data, Enable, Initialize, Crc, CrcError);


input Clk;
input Reset;
input [3:0] Data;
input Enable;
input Initialize;

output [31:0] Crc;
output CrcError;

reg  [31:0] Crc;

wire [31:0] CrcNext;


assign CrcNext[0] = Enable & (Data[0] ^ Crc[28]); 
assign CrcNext[1] = Enable & (Data[1] ^ Data[0] ^ Crc[28] ^ Crc[29]); 
assign CrcNext[2] = Enable & (Data[2] ^ Data[1] ^ Data[0] ^ Crc[28] ^ Crc[29] ^ Crc[30]); 
assign CrcNext[3] = Enable & (Data[3] ^ Data[2] ^ Data[1] ^ Crc[29] ^ Crc[30] ^ Crc[31]); 
assign CrcNext[4] = (Enable & (Data[3] ^ Data[2] ^ Data[0] ^ Crc[28] ^ Crc[30] ^ Crc[31])) ^ Crc[0]; 
assign CrcNext[5] = (Enable & (Data[3] ^ Data[1] ^ Data[0] ^ Crc[28] ^ Crc[29] ^ Crc[31])) ^ Crc[1]; 
assign CrcNext[6] = (Enable & (Data[2] ^ Data[1] ^ Crc[29] ^ Crc[30])) ^ Crc[ 2]; 
assign CrcNext[7] = (Enable & (Data[3] ^ Data[2] ^ Data[0] ^ Crc[28] ^ Crc[30] ^ Crc[31])) ^ Crc[3]; 
assign CrcNext[8] = (Enable & (Data[3] ^ Data[1] ^ Data[0] ^ Crc[28] ^ Crc[29] ^ Crc[31])) ^ Crc[4]; 
assign CrcNext[9] = (Enable & (Data[2] ^ Data[1] ^ Crc[29] ^ Crc[30])) ^ Crc[5]; 
assign CrcNext[10] = (Enable & (Data[3] ^ Data[2] ^ Data[0] ^ Crc[28] ^ Crc[30] ^ Crc[31])) ^ Crc[6]; 
assign CrcNext[11] = (Enable & (Data[3] ^ Data[1] ^ Data[0] ^ Crc[28] ^ Crc[29] ^ Crc[31])) ^ Crc[7]; 
assign CrcNext[12] = (Enable & (Data[2] ^ Data[1] ^ Data[0] ^ Crc[28] ^ Crc[29] ^ Crc[30])) ^ Crc[8]; 
assign CrcNext[13] = (Enable & (Data[3] ^ Data[2] ^ Data[1] ^ Crc[29] ^ Crc[30] ^ Crc[31])) ^ Crc[9]; 
assign CrcNext[14] = (Enable & (Data[3] ^ Data[2] ^ Crc[30] ^ Crc[31])) ^ Crc[10]; 
assign CrcNext[15] = (Enable & (Data[3] ^ Crc[31])) ^ Crc[11]; 
assign CrcNext[16] = (Enable & (Data[0] ^ Crc[28])) ^ Crc[12]; 
assign CrcNext[17] = (Enable & (Data[1] ^ Crc[29])) ^ Crc[13]; 
assign CrcNext[18] = (Enable & (Data[2] ^ Crc[30])) ^ Crc[14]; 
assign CrcNext[19] = (Enable & (Data[3] ^ Crc[31])) ^ Crc[15]; 
assign CrcNext[20] = Crc[16]; 
assign CrcNext[21] = Crc[17]; 
assign CrcNext[22] = (Enable & (Data[0] ^ Crc[28])) ^ Crc[18]; 
assign CrcNext[23] = (Enable & (Data[1] ^ Data[0] ^ Crc[29] ^ Crc[28])) ^ Crc[19]; 
assign CrcNext[24] = (Enable & (Data[2] ^ Data[1] ^ Crc[30] ^ Crc[29])) ^ Crc[20]; 
assign CrcNext[25] = (Enable & (Data[3] ^ Data[2] ^ Crc[31] ^ Crc[30])) ^ Crc[21]; 
assign CrcNext[26] = (Enable & (Data[3] ^ Data[0] ^ Crc[31] ^ Crc[28])) ^ Crc[22]; 
assign CrcNext[27] = (Enable & (Data[1] ^ Crc[29])) ^ Crc[23]; 
assign CrcNext[28] = (Enable & (Data[2] ^ Crc[30])) ^ Crc[24]; 
assign CrcNext[29] = (Enable & (Data[3] ^ Crc[31])) ^ Crc[25]; 
assign CrcNext[30] = Crc[26]; 
assign CrcNext[31] = Crc[27]; 


always @ (posedge Clk or posedge Reset)
begin
  if (Reset)
    Crc <=  32'hffffffff;
  else
  if(Initialize)
    Crc <=  32'hffffffff;
  else
    Crc <=  CrcNext;
end

assign CrcError = Crc[31:0] != 32'hc704dd7b;  // CRC not equal to magic number

endmodule


//////////////////////////////////////////////////////////////////////
////                                                              ////
////  eth_rxstatem.v                                              ////
////                                                              ////
////  This file is part of the Ethernet IP core project           ////
////  http://www.opencores.org/project,ethmac                     ////
////                                                              ////
////  Author(s):                                                  ////
////      - Igor Mohor (igorM@opencores.org)                      ////
////      - Novan Hartadi (novan@vlsi.itb.ac.id)                  ////
////      - Mahmud Galela (mgalela@vlsi.itb.ac.id)                ////
////                                                              ////
////  All additional information is avaliable in the Readme.txt   ////
////  file.                                                       ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
////                                                              ////
//// Copyright (C) 2001 Authors                                   ////
////                                                              ////
//// This source file may be used and distributed without         ////
//// restriction provided that this copyright statement is not    ////
//// removed from the file and that any derivative work contains  ////
//// the original copyright notice and the associated disclaimer. ////
////                                                              ////
//// This source file is free software; you can redistribute it   ////
//// and/or modify it under the terms of the GNU Lesser General   ////
//// Public License as published by the Free Software Foundation; ////
//// either version 2.1 of the License, or (at your option) any   ////
//// later version.                                               ////
////                                                              ////
//// This source is distributed in the hope that it will be       ////
//// useful, but WITHOUT ANY WARRANTY; without even the implied   ////
//// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      ////
//// PURPOSE.  See the GNU Lesser General Public License for more ////
//// details.                                                     ////
////                                                              ////
//// You should have received a copy of the GNU Lesser General    ////
//// Public License along with this source; if not, download it   ////
//// from http://www.opencores.org/lgpl.shtml                     ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
//
// CVS Revision History
//
// $Log: not supported by cvs2svn $
// Revision 1.5  2002/01/23 10:28:16  mohor
// Link in the header changed.
//
// Revision 1.4  2001/10/19 08:43:51  mohor
// eth_timescale.v changed to timescale.v This is done because of the
// simulation of the few cores in a one joined project.
//
// Revision 1.3  2001/10/18 12:07:11  mohor
// Status signals changed, Adress decoding changed, interrupt controller
// added.
//
// Revision 1.2  2001/09/11 14:17:00  mohor
// Few little NCSIM warnings fixed.
//
// Revision 1.1  2001/08/06 14:44:29  mohor
// A define FPGA added to select between Artisan RAM (for ASIC) and Block Ram (For Virtex).
// Include files fixed to contain no path.
// File names and module names changed ta have a eth_ prologue in the name.
// File eth_timescale.v is used to define timescale
// All pin names on the top module are changed to contain _I, _O or _OE at the end.
// Bidirectional signal MDIO is changed to three signals (Mdc_O, Mdi_I, Mdo_O
// and Mdo_OE. The bidirectional signal must be created on the top level. This
// is done due to the ASIC tools.
//
// Revision 1.1  2001/07/30 21:23:42  mohor
// Directory structure changed. Files checked and joind together.
//
// Revision 1.2  2001/07/03 12:55:41  mohor
// Minor changes because of the synthesys warnings.
//
//
// Revision 1.1  2001/06/27 21:26:19  mohor
// Initial release of the RxEthMAC module.
//
//
//
//


module eth_rxstatem (MRxClk, Reset, MRxDV, ByteCntEq0, ByteCntGreat2, Transmitting, MRxDEq5, MRxDEqD, 
                     IFGCounterEq24, ByteCntMaxFrame, StateData, StateIdle, StatePreamble, StateSFD, 
                     StateDrop
                    );

input         MRxClk;
input         Reset;
input         MRxDV;
input         ByteCntEq0;
input         ByteCntGreat2;
input         MRxDEq5;
input         Transmitting;
input         MRxDEqD;
input         IFGCounterEq24;
input         ByteCntMaxFrame;

output [1:0]  StateData;
output        StateIdle;
output        StateDrop;
output        StatePreamble;
output        StateSFD;

reg           StateData0;
reg           StateData1;
reg           StateIdle;
reg           StateDrop;
reg           StatePreamble;
reg           StateSFD;

wire          StartIdle;
wire          StartDrop;
wire          StartData0;
wire          StartData1;
wire          StartPreamble;
wire          StartSFD;


// Defining the next state
assign StartIdle = ~MRxDV & (StateDrop | StatePreamble | StateSFD | (|StateData));

assign StartPreamble = MRxDV & ~MRxDEq5 & (StateIdle & ~Transmitting);

assign StartSFD = MRxDV & MRxDEq5 & (StateIdle & ~Transmitting | StatePreamble);

assign StartData0 = MRxDV & (StateSFD & MRxDEqD & IFGCounterEq24 | StateData1);

assign StartData1 = MRxDV & StateData0 & (~ByteCntMaxFrame);

assign StartDrop = MRxDV & (StateIdle & Transmitting | StateSFD & ~IFGCounterEq24 &
                   MRxDEqD |  StateData0 &  ByteCntMaxFrame);

// Rx State Machine
always @ (posedge MRxClk or posedge Reset)
begin
  if(Reset)
    begin
      StateIdle     <=  1'b0;
      StateDrop     <=  1'b1;
      StatePreamble <=  1'b0;
      StateSFD      <=  1'b0;
      StateData0    <=  1'b0;
      StateData1    <=  1'b0;
    end
  else
    begin
      if(StartPreamble | StartSFD | StartDrop)
        StateIdle <=  1'b0;
      else
      if(StartIdle)
        StateIdle <=  1'b1;

      if(StartIdle)
        StateDrop <=  1'b0;
      else
      if(StartDrop)
        StateDrop <=  1'b1;

      if(StartSFD | StartIdle | StartDrop)
        StatePreamble <=  1'b0;
      else
      if(StartPreamble)
        StatePreamble <=  1'b1;

      if(StartPreamble | StartIdle | StartData0 | StartDrop)
        StateSFD <=  1'b0;
      else
      if(StartSFD)
        StateSFD <=  1'b1;

      if(StartIdle | StartData1 | StartDrop)
        StateData0 <=  1'b0;
      else
      if(StartData0)
        StateData0 <=  1'b1;

      if(StartIdle | StartData0 | StartDrop)
        StateData1 <=  1'b0;
      else
      if(StartData1)
        StateData1 <=  1'b1;
    end
end

assign StateData[1:0] = {StateData1, StateData0};

endmodule


//////////////////////////////////////////////////////////////////////
////                                                              ////
////  eth_rxcounters.v                                            ////
////                                                              ////
////  This file is part of the Ethernet IP core project           ////
////  http://www.opencores.org/project,ethmac                     ////
////                                                              ////
////  Author(s):                                                  ////
////      - Igor Mohor (igorM@opencores.org)                      ////
////      - Novan Hartadi (novan@vlsi.itb.ac.id)                  ////
////      - Mahmud Galela (mgalela@vlsi.itb.ac.id)                ////
////                                                              ////
////  All additional information is avaliable in the Readme.txt   ////
////  file.                                                       ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
////                                                              ////
//// Copyright (C) 2001 Authors                                   ////
////                                                              ////
//// This source file may be used and distributed without         ////
//// restriction provided that this copyright statement is not    ////
//// removed from the file and that any derivative work contains  ////
//// the original copyright notice and the associated disclaimer. ////
////                                                              ////
//// This source file is free software; you can redistribute it   ////
//// and/or modify it under the terms of the GNU Lesser General   ////
//// Public License as published by the Free Software Foundation; ////
//// either version 2.1 of the License, or (at your option) any   ////
//// later version.                                               ////
////                                                              ////
//// This source is distributed in the hope that it will be       ////
//// useful, but WITHOUT ANY WARRANTY; without even the implied   ////
//// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      ////
//// PURPOSE.  See the GNU Lesser General Public License for more ////
//// details.                                                     ////
////                                                              ////
//// You should have received a copy of the GNU Lesser General    ////
//// Public License along with this source; if not, download it   ////
//// from http://www.opencores.org/lgpl.shtml                     ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
//
// CVS Revision History
//
// $Log: not supported by cvs2svn $
// Revision 1.5  2002/02/15 11:13:29  mohor
// Format of the file changed a bit.
//
// Revision 1.4  2002/02/14 20:19:41  billditt
// Modified for Address Checking,
// addition of eth_addrcheck.v
//
// Revision 1.3  2002/01/23 10:28:16  mohor
// Link in the header changed.
//
// Revision 1.2  2001/10/19 08:43:51  mohor
// eth_timescale.v changed to timescale.v This is done because of the
// simulation of the few cores in a one joined project.
//
// Revision 1.1  2001/08/06 14:44:29  mohor
// A define FPGA added to select between Artisan RAM (for ASIC) and Block Ram (For Virtex).
// Include files fixed to contain no path.
// File names and module names changed ta have a eth_ prologue in the name.
// File eth_timescale.v is used to define timescale
// All pin names on the top module are changed to contain _I, _O or _OE at the end.
// Bidirectional signal MDIO is changed to three signals (Mdc_O, Mdi_I, Mdo_O
// and Mdo_OE. The bidirectional signal must be created on the top level. This
// is done due to the ASIC tools.
//
// Revision 1.1  2001/07/30 21:23:42  mohor
// Directory structure changed. Files checked and joind together.
//
// Revision 1.1  2001/06/27 21:26:19  mohor
// Initial release of the RxEthMAC module.
//
//
//
//
//
//

module eth_rxcounters 
  (
   MRxClk, Reset, MRxDV, StateIdle, StateSFD, StateData, StateDrop, StatePreamble, 
   MRxDEqD, DlyCrcEn, DlyCrcCnt, Transmitting, MaxFL, r_IFG, HugEn, IFGCounterEq24, 
   ByteCntEq0, ByteCntEq1, ByteCntEq2,ByteCntEq3,ByteCntEq4,ByteCntEq5, ByteCntEq6,
   ByteCntEq7, ByteCntGreat2, ByteCntSmall7, ByteCntMaxFrame, ByteCntOut
   );

input         MRxClk;
input         Reset;
input         MRxDV;
input         StateSFD;
input [1:0]   StateData;
input         MRxDEqD;
input         StateIdle;
input         StateDrop;
input         DlyCrcEn;
input         StatePreamble;
input         Transmitting;
input         HugEn;
input [15:0]  MaxFL;
input         r_IFG;

output        IFGCounterEq24;           // IFG counter reaches 9600 ns (960 ns)
output [3:0]  DlyCrcCnt;                // Delayed CRC counter
output        ByteCntEq0;               // Byte counter = 0
output        ByteCntEq1;               // Byte counter = 1
output        ByteCntEq2;               // Byte counter = 2  
output        ByteCntEq3;               // Byte counter = 3  
output        ByteCntEq4;               // Byte counter = 4  
output        ByteCntEq5;               // Byte counter = 5  
output        ByteCntEq6;               // Byte counter = 6
output        ByteCntEq7;               // Byte counter = 7
output        ByteCntGreat2;            // Byte counter > 2
output        ByteCntSmall7;            // Byte counter < 7
output        ByteCntMaxFrame;          // Byte counter = MaxFL
output [15:0] ByteCntOut;               // Byte counter

wire          ResetByteCounter;
wire          IncrementByteCounter;
wire          ResetIFGCounter;
wire          IncrementIFGCounter;
wire          ByteCntMax;

reg   [15:0]  ByteCnt;
reg   [3:0]   DlyCrcCnt;
reg   [4:0]   IFGCounter;

wire  [15:0]  ByteCntDelayed;



assign ResetByteCounter = MRxDV & (StateSFD & MRxDEqD | StateData[0] & ByteCntMaxFrame);

assign IncrementByteCounter = ~ResetByteCounter & MRxDV & 
                              (StatePreamble | StateSFD | StateIdle & ~Transmitting |
                               StateData[1] & ~ByteCntMax & ~(DlyCrcEn & |DlyCrcCnt)
                              );


always @ (posedge MRxClk or posedge Reset)
begin
  if(Reset)
    ByteCnt[15:0] <=  16'd0;
  else
    begin
      if(ResetByteCounter)
        ByteCnt[15:0] <=  16'd0;
      else
      if(IncrementByteCounter)
        ByteCnt[15:0] <=  ByteCnt[15:0] + 16'd1;
     end
end

assign ByteCntDelayed = ByteCnt + 16'd4;
assign ByteCntOut = DlyCrcEn ? ByteCntDelayed : ByteCnt;

assign ByteCntEq0       = ByteCnt == 16'd0;
assign ByteCntEq1       = ByteCnt == 16'd1;
assign ByteCntEq2       = ByteCnt == 16'd2; 
assign ByteCntEq3       = ByteCnt == 16'd3; 
assign ByteCntEq4       = ByteCnt == 16'd4; 
assign ByteCntEq5       = ByteCnt == 16'd5; 
assign ByteCntEq6       = ByteCnt == 16'd6;
assign ByteCntEq7       = ByteCnt == 16'd7;
assign ByteCntGreat2    = ByteCnt >  16'd2;
assign ByteCntSmall7    = ByteCnt <  16'd7;
assign ByteCntMax       = ByteCnt == 16'hffff;
assign ByteCntMaxFrame  = ByteCnt == MaxFL[15:0] & ~HugEn;


assign ResetIFGCounter = StateSFD  &  MRxDV & MRxDEqD | StateDrop;

assign IncrementIFGCounter = ~ResetIFGCounter & (StateDrop | StateIdle | StatePreamble | StateSFD) & ~IFGCounterEq24;

always @ (posedge MRxClk or posedge Reset)
begin
  if(Reset)
    IFGCounter[4:0] <=  5'h0;
  else
    begin
      if(ResetIFGCounter)
        IFGCounter[4:0] <=  5'h0;
      else
      if(IncrementIFGCounter)
        IFGCounter[4:0] <=  IFGCounter[4:0] + 5'd1; 
    end
end



assign IFGCounterEq24 = (IFGCounter[4:0] == 5'h18) | r_IFG; // 24*400 = 9600 ns or r_IFG is set to 1


always @ (posedge MRxClk or posedge Reset)
begin
  if(Reset)
    DlyCrcCnt[3:0] <=  4'h0;
  else
    begin
      if(DlyCrcCnt[3:0] == 4'h9)
        DlyCrcCnt[3:0] <=  4'h0;
      else
      if(DlyCrcEn & StateSFD)
        DlyCrcCnt[3:0] <=  4'h1;
      else
      if(DlyCrcEn & (|DlyCrcCnt[3:0]))
        DlyCrcCnt[3:0] <=  DlyCrcCnt[3:0] + 4'd1;
    end
end


endmodule


//////////////////////////////////////////////////////////////////////
////                                                              ////
////  eth_rxaddrcheck.v                                           ////
////                                                              ////
////  This file is part of the Ethernet IP core project           ////
////  http://www.opencores.org/project,ethmac/                    ////
////                                                              ////
////  Author(s):                                                  ////
////      - Bill Dittenhofer (billditt@aol.com)                   ////
////      - Olof Kindgren    (olof@opencores.org)                 ////
////                                                              ////
////  All additional information is avaliable in the Readme.txt   ////
////  file.                                                       ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
////                                                              ////
//// Copyright (C) 2001, 2011 Authors                             ////
////                                                              ////
//// This source file may be used and distributed without         ////
//// restriction provided that this copyright statement is not    ////
//// removed from the file and that any derivative work contains  ////
//// the original copyright notice and the associated disclaimer. ////
////                                                              ////
//// This source file is free software; you can redistribute it   ////
//// and/or modify it under the terms of the GNU Lesser General   ////
//// Public License as published by the Free Software Foundation; ////
//// either version 2.1 of the License, or (at your option) any   ////
//// later version.                                               ////
////                                                              ////
//// This source is distributed in the hope that it will be       ////
//// useful, but WITHOUT ANY WARRANTY; without even the implied   ////
//// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      ////
//// PURPOSE.  See the GNU Lesser General Public License for more ////
//// details.                                                     ////
////                                                              ////
//// You should have received a copy of the GNU Lesser General    ////
//// Public License along with this source; if not, download it   ////
//// from http://www.opencores.org/lgpl.shtml                     ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
//
// 2011-07-06 Olof Kindgren <olof@opencores.org>
// Reset AdressMiss when a new frame arrives. Otherwise it will report
// the last value when a frame is less than seven bytes
//
// CVS Revision History
//
// $Log: not supported by cvs2svn $
// Revision 1.8  2002/11/19 17:34:52  mohor
// AddressMiss status is connecting to the Rx BD. AddressMiss is identifying
// that a frame was received because of the promiscous mode.
//
// Revision 1.7  2002/09/04 18:41:06  mohor
// Bug when last byte of destination address was not checked fixed.
//
// Revision 1.6  2002/03/20 15:14:11  mohor
// When in promiscous mode some frames were not received correctly. Fixed.
//
// Revision 1.5  2002/03/02 21:06:32  mohor
// Log info was missing.
//
//
// Revision 1.1  2002/02/08 12:51:54  ditt
// Initial release of the ethernet addresscheck module.
//
//
//
//
//

module eth_rxaddrcheck(MRxClk,  Reset, RxData, Broadcast ,r_Bro ,r_Pro,
                       ByteCntEq2, ByteCntEq3, ByteCntEq4, ByteCntEq5,
                       ByteCntEq6, ByteCntEq7, HASH0, HASH1, ByteCntEq0,
                       CrcHash,    CrcHashGood, StateData, RxEndFrm,
                       Multicast, MAC, RxAbort, AddressMiss, PassAll,
                       ControlFrmAddressOK
                      );


  input        MRxClk; 
  input        Reset; 
  input [7:0]  RxData; 
  input        Broadcast; 
  input        r_Bro; 
  input        r_Pro; 
  input        ByteCntEq0;
  input        ByteCntEq2;
  input        ByteCntEq3;
  input        ByteCntEq4;
  input        ByteCntEq5;
  input        ByteCntEq6;
  input        ByteCntEq7;
  input [31:0] HASH0; 
  input [31:0] HASH1; 
  input [5:0]  CrcHash; 
  input        CrcHashGood; 
  input        Multicast; 
  input [47:0] MAC;
  input [1:0]  StateData;
  input        RxEndFrm;
  input        PassAll;
  input        ControlFrmAddressOK;
  
  output       RxAbort;
  output       AddressMiss;

 wire BroadcastOK;
 wire ByteCntEq2;
 wire ByteCntEq3;
 wire ByteCntEq4; 
 wire ByteCntEq5;
 wire RxAddressInvalid;
 wire RxCheckEn;
 wire HashBit;
 wire [31:0] IntHash;
 reg [7:0]  ByteHash;
 reg MulticastOK;
 reg UnicastOK;
 reg RxAbort;
 reg AddressMiss;
 
assign RxAddressInvalid = ~(UnicastOK | BroadcastOK | MulticastOK | r_Pro);
 
assign BroadcastOK = Broadcast & ~r_Bro;
 
assign RxCheckEn   = | StateData;
 
 // Address Error Reported at end of address cycle
 // RxAbort clears after one cycle
 
always @ (posedge MRxClk or posedge Reset)
begin
  if(Reset)
    RxAbort <=  1'b0;
  else if(RxAddressInvalid & ByteCntEq7 & RxCheckEn)
    RxAbort <=  1'b1;
  else
    RxAbort <=  1'b0;
end
 

// This ff holds the "Address Miss" information that is written to the RX BD status.
always @ (posedge MRxClk or posedge Reset)
begin
  if(Reset)
    AddressMiss <=  1'b0;
  else if(ByteCntEq0)
    AddressMiss <=  1'b0;
  else if(ByteCntEq7 & RxCheckEn)
    AddressMiss <=  (~(UnicastOK | BroadcastOK | MulticastOK | (PassAll & ControlFrmAddressOK)));
end


// Hash Address Check, Multicast
always @ (posedge MRxClk or posedge Reset)
begin
  if(Reset)
    MulticastOK <=  1'b0;
  else if(RxEndFrm | RxAbort)
    MulticastOK <=  1'b0;
  else if(CrcHashGood & Multicast)
    MulticastOK <=  HashBit;
end
 
 
// Address Detection (unicast)
// start with ByteCntEq2 due to delay of addres from RxData
always @ (posedge MRxClk or posedge Reset)
begin
  if(Reset)
    UnicastOK <=  1'b0;
  else
  if(RxCheckEn & ByteCntEq2)
    UnicastOK <=    RxData[7:0] == MAC[47:40];
  else
  if(RxCheckEn & ByteCntEq3)
    UnicastOK <=  ( RxData[7:0] == MAC[39:32]) & UnicastOK;
  else
  if(RxCheckEn & ByteCntEq4)
    UnicastOK <=  ( RxData[7:0] == MAC[31:24]) & UnicastOK;
  else
  if(RxCheckEn & ByteCntEq5)
    UnicastOK <=  ( RxData[7:0] == MAC[23:16]) & UnicastOK;
  else
  if(RxCheckEn & ByteCntEq6)
    UnicastOK <=  ( RxData[7:0] == MAC[15:8])  & UnicastOK;
  else
  if(RxCheckEn & ByteCntEq7)
    UnicastOK <=  ( RxData[7:0] == MAC[7:0])   & UnicastOK;
  else
  if(RxEndFrm | RxAbort)
    UnicastOK <=  1'b0;
end
   
assign IntHash = (CrcHash[5])? HASH1 : HASH0;
  
always@(CrcHash or IntHash)
begin
  case(CrcHash[4:3])
    2'b00: ByteHash = IntHash[7:0];
    2'b01: ByteHash = IntHash[15:8];
    2'b10: ByteHash = IntHash[23:16];
    2'b11: ByteHash = IntHash[31:24];
  endcase
end
      
assign HashBit = ByteHash[CrcHash[2:0]];


endmodule

//`include "eth_l3_checksum.v"

module eth_rxethmac (MRxClk, MRxDV, MRxD, Reset, Transmitting, MaxFL, r_IFG,
                     HugEn, DlyCrcEn, RxData, RxValid, RxStartFrm, RxEndFrm,
                     ByteCnt, ByteCntEq0, ByteCntGreat2, ByteCntMaxFrame,
                     CrcError, StateIdle, StatePreamble, StateSFD, StateData,
                     MAC, r_Pro, r_Bro,r_HASH0, r_HASH1, RxAbort, AddressMiss,
                     PassAll, ControlFrmAddressOK
                    );

input         MRxClk;
input         MRxDV;
input   [3:0] MRxD;
input         Transmitting;
input         HugEn;
input         DlyCrcEn;
input  [15:0] MaxFL;
input         r_IFG;
input         Reset;
input  [47:0] MAC;     //  Station Address  
input         r_Bro;   //  broadcast disable
input         r_Pro;   //  promiscuous enable 
input [31:0]  r_HASH0; //  lower 4 bytes Hash Table
input [31:0]  r_HASH1; //  upper 4 bytes Hash Table
input         PassAll;
input         ControlFrmAddressOK;

output  [7:0] RxData;
output        RxValid;
output        RxStartFrm;
output        RxEndFrm;
output [15:0] ByteCnt;
output        ByteCntEq0;
output        ByteCntGreat2;
output        ByteCntMaxFrame;
output        CrcError;
output        StateIdle;
output        StatePreamble;
output        StateSFD;
output  [1:0] StateData;
output        RxAbort;
output        AddressMiss;

reg     [7:0] RxData;
reg           RxValid;
reg           RxStartFrm;
reg           RxEndFrm;
reg           Broadcast;
reg           Multicast;
reg     [5:0] CrcHash;
reg           CrcHashGood;
reg           DelayData;
reg     [7:0] LatchedByte;
reg     [7:0] RxData_d;
reg           RxValid_d;
reg           RxStartFrm_d;
reg           RxEndFrm_d;

wire          MRxDEqD;
wire          MRxDEq5;
wire          StateDrop;
wire          ByteCntEq1;
wire          ByteCntEq2;
wire          ByteCntEq3;
wire          ByteCntEq4;
wire          ByteCntEq5;
wire          ByteCntEq6;
wire          ByteCntEq7;
wire          ByteCntSmall7;
wire   [31:0] Crc;
wire          Enable_Crc;
wire          Initialize_Crc;
wire    [3:0] Data_Crc;
wire          GenerateRxValid;
wire          GenerateRxStartFrm;
wire          GenerateRxEndFrm;
wire          DribbleRxEndFrm;
wire    [3:0] DlyCrcCnt;
wire          IFGCounterEq24;
wire    [15:0] CheckSum;
wire           CSready;
assign MRxDEqD = MRxD == 4'hd;
assign MRxDEq5 = MRxD == 4'h5;

  initial begin 
       RxData=0;
       RxData_d=0;
       RxStartFrm=0;
       RxEndFrm=0;
       RxStartFrm_d=0;
       RxEndFrm_d=0;  
       end
// Rx State Machine module
eth_rxstatem rxstatem1
  (.MRxClk(MRxClk),
   .Reset(Reset),
   .MRxDV(MRxDV),
   .ByteCntEq0(ByteCntEq0),
   .ByteCntGreat2(ByteCntGreat2),
   .Transmitting(Transmitting),
   .MRxDEq5(MRxDEq5),
   .MRxDEqD(MRxDEqD),
   .IFGCounterEq24(IFGCounterEq24),
   .ByteCntMaxFrame(ByteCntMaxFrame),
   .StateData(StateData),
   .StateIdle(StateIdle),
   .StatePreamble(StatePreamble),
   .StateSFD(StateSFD),
   .StateDrop(StateDrop)
   );


// Rx Counters module
eth_rxcounters rxcounters1
  (.MRxClk(MRxClk),
   .Reset(Reset),
   .MRxDV(MRxDV),
   .StateIdle(StateIdle),
   .StateSFD(StateSFD),
   .StateData(StateData),
   .StateDrop(StateDrop),
   .StatePreamble(StatePreamble),
   .MRxDEqD(MRxDEqD),
   .DlyCrcEn(DlyCrcEn),
   .DlyCrcCnt(DlyCrcCnt),
   .Transmitting(Transmitting),
   .MaxFL(MaxFL),
   .r_IFG(r_IFG),
   .HugEn(HugEn),
   .IFGCounterEq24(IFGCounterEq24),
   .ByteCntEq0(ByteCntEq0),
   .ByteCntEq1(ByteCntEq1),
   .ByteCntEq2(ByteCntEq2),
   .ByteCntEq3(ByteCntEq3),
   .ByteCntEq4(ByteCntEq4),
   .ByteCntEq5(ByteCntEq5),
   .ByteCntEq6(ByteCntEq6),
   .ByteCntEq7(ByteCntEq7),
   .ByteCntGreat2(ByteCntGreat2),
   .ByteCntSmall7(ByteCntSmall7),
   .ByteCntMaxFrame(ByteCntMaxFrame),
   .ByteCntOut(ByteCnt)
   );

// Rx Address Check

eth_rxaddrcheck rxaddrcheck1
  (.MRxClk(MRxClk),
   .Reset( Reset),
   .RxData(RxData),
   .Broadcast (Broadcast),
   .r_Bro (r_Bro),
   .r_Pro(r_Pro),
   .ByteCntEq6(ByteCntEq6),
   .ByteCntEq7(ByteCntEq7),
   .ByteCntEq2(ByteCntEq2),
   .ByteCntEq3(ByteCntEq3),
   .ByteCntEq4(ByteCntEq4),
   .ByteCntEq5(ByteCntEq5),
   .HASH0(r_HASH0),
   .HASH1(r_HASH1),
   .ByteCntEq0(ByteCntEq0),
   .CrcHash(CrcHash),
   .CrcHashGood(CrcHashGood),
   .StateData(StateData),
   .Multicast(Multicast),
   .MAC(MAC),
   .RxAbort(RxAbort),
   .RxEndFrm(RxEndFrm),
   .AddressMiss(AddressMiss),
   .PassAll(PassAll),
   .ControlFrmAddressOK(ControlFrmAddressOK)
   );


assign Enable_Crc = MRxDV & (|StateData & ~ByteCntMaxFrame);
assign Initialize_Crc = StateSFD | DlyCrcEn & (|DlyCrcCnt[3:0]) &
                        DlyCrcCnt[3:0] < 4'h9;

assign Data_Crc[0] = MRxD[3];
assign Data_Crc[1] = MRxD[2];
assign Data_Crc[2] = MRxD[1];
assign Data_Crc[3] = MRxD[0];


// Connecting module Crc
eth_crc crcrx
  (.Clk(MRxClk),
   .Reset(Reset),
   .Data(Data_Crc),
   .Enable(Enable_Crc),
   .Initialize(Initialize_Crc), 
   .Crc(Crc),
   .CrcError(CrcError)
   );

 eth_l3_checksum checkSumcalc
 (
   .MRxClk(MRxClk),
   .Reset(Reset),
   .RxData(RxData),
   .ByteCnt(ByteCnt),
   .CheckSum(CheckSum), 
   .CSready(CSready)
 );

// Latching CRC for use in the hash table
always @ (posedge MRxClk)
begin
  CrcHashGood <=  StateData[0] & ByteCntEq6;
end

always @ (posedge MRxClk)
begin
  if(Reset | StateIdle)
    CrcHash[5:0] <=  6'h0;
  else
  if(StateData[0] & ByteCntEq6)
    CrcHash[5:0] <=  Crc[31:26];
end

// Output byte stream
always @ (posedge MRxClk or posedge Reset)
begin
  if(Reset)
    begin
      RxData_d[7:0]      <=  8'h0;
      DelayData          <=  1'b0;
      LatchedByte[7:0]   <=  8'h0;
      RxData[7:0]        <=  8'h0;
    end
  else
    begin
      // Latched byte
      LatchedByte[7:0]   <=  {MRxD[3:0], LatchedByte[7:4]};
      DelayData          <=  StateData[0];

      if(GenerateRxValid)
        // Data goes through only in data state 
        RxData_d[7:0] <=  LatchedByte[7:0] & {8{|StateData}};
      else
      if(~DelayData)
        // Delaying data to be valid for two cycles.
        // Zero when not active.
        RxData_d[7:0] <=  8'h0;

      RxData[7:0] <=  RxData_d[7:0];          // Output data byte
    end
end



always @ (posedge MRxClk or posedge Reset)
begin
  if(Reset)
    Broadcast <=  1'b0;
  else
    begin      
      if(StateData[0] & ~(&LatchedByte[7:0]) & ByteCntSmall7)
        Broadcast <=  1'b0;
      else
      if(StateData[0] & (&LatchedByte[7:0]) & ByteCntEq1)
        Broadcast <=  1'b1;
      else
      if(RxAbort | RxEndFrm)
        Broadcast <=  1'b0;
    end
end


always @ (posedge MRxClk or posedge Reset)
begin
  if(Reset)
    Multicast <=  1'b0;
  else
    begin      
      if(StateData[0] & ByteCntEq1 & LatchedByte[0])
        Multicast <=  1'b1;
      else if(RxAbort | RxEndFrm)
      Multicast <=  1'b0;
    end
end


assign GenerateRxValid = StateData[0] & (~ByteCntEq0 | DlyCrcCnt >= 4'h3);

always @ (posedge MRxClk or posedge Reset)
begin
  if(Reset)
    begin
      RxValid_d <=  1'b0;
      RxValid   <=  1'b0;
    end
  else
    begin
      RxValid_d <=  GenerateRxValid;
      RxValid   <=  RxValid_d;
    end
end


assign GenerateRxStartFrm = StateData[0] &
                            ((ByteCntEq1 & ~DlyCrcEn) |
                            ((DlyCrcCnt == 4'h3) & DlyCrcEn));

always @ (posedge MRxClk or posedge Reset)
begin
  if(Reset)
    begin
      RxStartFrm_d <=  1'b0;
      RxStartFrm   <=  1'b0;
    end
  else
    begin
      RxStartFrm_d <=  GenerateRxStartFrm;
      RxStartFrm   <=  RxStartFrm_d;
    end
end


assign GenerateRxEndFrm = StateData[0] &
                          (~MRxDV & ByteCntGreat2 | ByteCntMaxFrame);
assign DribbleRxEndFrm  = StateData[1] &  ~MRxDV & ByteCntGreat2;


always @ (posedge MRxClk or posedge Reset)
begin
  if(Reset)
    begin
      RxEndFrm_d <=  1'b0;
      RxEndFrm   <=  1'b0;
    end
  else
    begin
      RxEndFrm_d <=  GenerateRxEndFrm;
      RxEndFrm   <=  RxEndFrm_d | DribbleRxEndFrm;
    end
end


endmodule

   
 module eth_l3_checksum 
   (
     MRxClk ,Reset, RxData , ByteCnt, CheckSum ,CSready
   );

input    MRxClk;
input    Reset;
input [7:0] RxData;
input [15:0] ByteCnt;
output [15:0] CheckSum;
output        CSready;

reg   [15:0]   CheckSum;
reg   [31:0]   Sum;
reg            CSready;
reg   [1:0]    StartCalc;
reg            Divided_2_clk ;
reg            Divided_4_clk ;
reg [7:0] prev_latched_Rx;
reg [7:0] prev_latched_Rx1;

 initial Divided_2_clk=0;
 initial Divided_4_clk=0;

always @ (posedge MRxClk)
    begin
       Divided_2_clk <=  MRxClk^Divided_2_clk;
       if (ByteCnt[15:0] >= 16'h17 & ByteCnt[15:0] < (16'h17+16'd20))
           begin
           prev_latched_Rx[7:0] <= RxData[7:0];
           prev_latched_Rx1[7:0] <= prev_latched_Rx[7:0];
           end

    end

always @ (posedge Divided_2_clk)
      Divided_4_clk <= Divided_4_clk ^ Divided_2_clk;
       

always @ (posedge  Divided_2_clk or posedge Reset )
begin
    if (Reset)
        begin
        CheckSum[15:0] <= 16'd0;
        CSready <= 1'd0;
        end
    else
       if (ByteCnt[15:0]==16'h15)
           StartCalc[0] <= (RxData[7:0] == 8'h8);
       else
       if (ByteCnt[15:0]==16'h16)
           begin
           StartCalc[0] <= (RxData[7:0] == 8'h0) & StartCalc[0] ;
           CheckSum[15:0] <= 16'h0;
           Sum[31:0] <= 32'h0;
           CSready <= 1'b0;
           end
       else     
       if (ByteCnt[15:0] >= 16'h17 & ByteCnt[15:0] < (16'h17+16'd20))
           begin
           StartCalc[1]<= (ByteCnt[15:0] > 16'h17) & StartCalc[0] ;
           end
       else
         StartCalc[1:0] <= 2'h0;   
         
   if (ByteCnt[15:0]-16'h17== 16'd20)
       begin
         CSready <= 1'b1;
         CheckSum[15:0] <= ~(Sum[15:0]+Sum[31:16]);
       end
       
   end

 always @ (negedge Divided_4_clk)
 begin
      if (&StartCalc)
        Sum[31:0]<= Sum[31:0] + {prev_latched_Rx1[7:0] , RxData[7:0]};
      
  end

  

endmodule
"""

ge_1000baseX_rx = """
//////////////////////////////////////////////////////////////////////
////                                                              ////
////  File name "ge_1000baseX_rx.v"                               ////
////                                                              ////
////  This file is part of the :                                  ////
////                                                              ////
//// "1000BASE-X IEEE 802.3-2008 Clause 36 - PCS project"         ////
////                                                              ////
////  http://opencores.org/project,1000base-x                     ////
////                                                              ////
////  Author(s):                                                  ////
////      - D.W.Pegler Cambridge Broadband Networks Ltd           ////
////                                                              ////
////      { peglerd@gmail.com, dwp@cambridgebroadand.com }        ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
////                                                              ////
//// Copyright (C) 2009 AUTHORS. All rights reserved.             ////
////                                                              ////
//// This source file may be used and distributed without         ////
//// restriction provided that this copyright statement is not    ////
//// removed from the file and that any derivative work contains  ////
//// the original copyright notice and the associated disclaimer. ////
////                                                              ////
//// This source file is free software; you can redistribute it   ////
//// and/or modify it under the terms of the GNU Lesser General   ////
//// Public License as published by the Free Software Foundation; ////
//// either version 2.1 of the License, or (at your option) any   ////
//// later version.                                               ////
////                                                              ////
//// This source is distributed in the hope that it will be       ////
//// useful, but WITHOUT ANY WARRANTY; without even the implied   ////
//// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      ////
//// PURPOSE.  See the GNU Lesser General Public License for more ////
//// details.                                                     ////
////                                                              ////
//// You should have received a copy of the GNU Lesser General    ////
//// Public License along with this source; if not, download it   ////
//// from http://www.opencores.org/lgpl.shtml                     ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
////                                                              ////
//// This module is based on the coding method described in       ////
//// IEEE Std 802.3-2008 Clause 36 "Physical Coding Sublayer(PCS) ////
//// and Physical Medium Attachment (PMA) sublayer, type          ////
//// 1000BASE-X"; see :                                           ////
////                                                              ////
//// http://standards.ieee.org/about/get/802/802.3.html           ////
//// and                                                          ////
//// doc/802.3-2008_section3.pdf, Clause/Section 36.              ////
////                                                              ////
//////////////////////////////////////////////////////////////////////

`define GMII_BASIC_CTRL   'd00
`define GMII_BASIC_STATUS 'd02
`define GMII_PHY_ID1      'd04
`define GMII_PHY_ID2      'd06
`define GMII_AN_ADV       'd08
`define GMII_AN_LP_ADV    'd10
`define GMII_AN_EXPANSION 'd12
`define GMII_AN_NP        'd14
`define GMII_AN_LP_NP     'd16

//////////////////////////////////////////////////////////////////////
////                                                              ////
////  File name "ge_1000baseX_regs.v"                             ////
////                                                              ////
////  This file is part of the :                                  ////
////                                                              ////
//// "1000BASE-X IEEE 802.3-2008 Clause 36 - PCS project"         ////
////                                                              ////
////  http://opencores.org/project,1000base-x                     ////
////                                                              ////
////  Author(s):                                                  ////
////      - D.W.Pegler Cambridge Broadband Networks Ltd           ////
////                                                              ////
////      { peglerd@gmail.com, dwp@cambridgebroadand.com }        ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
////                                                              ////
//// Copyright (C) 2009 AUTHORS. All rights reserved.             ////
////                                                              ////
//// This source file may be used and distributed without         ////
//// restriction provided that this copyright statement is not    ////
//// removed from the file and that any derivative work contains  ////
//// the original copyright notice and the associated disclaimer. ////
////                                                              ////
//// This source file is free software; you can redistribute it   ////
//// and/or modify it under the terms of the GNU Lesser General   ////
//// Public License as published by the Free Software Foundation; ////
//// either version 2.1 of the License, or (at your option) any   ////
//// later version.                                               ////
////                                                              ////
//// This source is distributed in the hope that it will be       ////
//// useful, but WITHOUT ANY WARRANTY; without even the implied   ////
//// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      ////
//// PURPOSE.  See the GNU Lesser General Public License for more ////
//// details.                                                     ////
////                                                              ////
//// You should have received a copy of the GNU Lesser General    ////
//// Public License along with this source; if not, download it   ////
//// from http://www.opencores.org/lgpl.shtml                     ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
////                                                              ////
//// This module is based on the coding method described in       ////
//// IEEE Std 802.3-2008 Clause 36 "Physical Coding Sublayer(PCS) ////
//// and Physical Medium Attachment (PMA) sublayer, type          ////
//// 1000BASE-X"; see :                                           ////
////                                                              ////
//// http://standards.ieee.org/about/get/802/802.3.html           ////
//// and                                                          ////
//// doc/802.3-2008_section3.pdf, Clause/Section 36.              ////
////                                                              ////
//////////////////////////////////////////////////////////////////////

`define GMII_BASIC_CTRL   'd00
`define GMII_BASIC_STATUS 'd02
`define GMII_PHY_ID1      'd04
`define GMII_PHY_ID2      'd06
`define GMII_AN_ADV       'd08
`define GMII_AN_LP_ADV    'd10
`define GMII_AN_EXPANSION 'd12
`define GMII_AN_NP        'd14
`define GMII_AN_LP_NP     'd16
// XMIT Autonegotiation parameter - ctrl for the PCS TX state machine   
`define XMIT_IDLE           0
`define XMIT_CONFIGURATION  1
`define XMIT_DATA           2
   
`define RUDI_INVALID 0
`define RUDI_IDLE    1
`define RUDI_CONF    2
   
// Special K code-groups - K codes
`define K28_0_symbol 8'h1c
`define K28_1_symbol 8'h3c
`define K28_2_symbol 8'h5c
`define K28_3_symbol 8'h7c
`define K28_4_symbol 8'h9c
`define K28_5_symbol 8'hbc
`define K28_6_symbol 8'hdc
`define K28_7_symbol 8'hfc
`define K23_7_symbol 8'hf7
`define K27_7_symbol 8'hfb
`define K29_7_symbol 8'hfd
`define K30_7_symbol 8'hfe

// Special D code-groups - D codes   
`define D21_5_symbol  8'hb5
`define D2_2_symbol   8'h42
`define D5_6_symbol   8'hc5
`define D16_2_symbol  8'h50
`define D0_0_symbol   8'h00

`define D21_2_symbol  8'h55
`define D21_6_symbol  8'hd5

`define D6_6_symbol   8'hc6
`define D10_1_symbol  8'h2a
`define D3_3_symbol   8'h63
`define D27_7_symbol  8'hfb
`define D3_0_symbol   8'h03

`define D30_2_symbol  8'h5e
`define D12_4_symbol  8'h8c
`define D8_6_symbol   8'hc8
`define D13_7_symbol  8'hed

// Code group ordered_sets
`define I_CODE  4'b0001
`define I1_CODE 4'b0010
`define I2_CODE 4'b0011
`define C_CODE  4'b0100
`define C1_CODE 4'b0101
`define C2_CODE 4'b0110
`define R_CODE  4'b0111
`define S_CODE  4'b1000
`define T_CODE  4'b1001
`define V_CODE  4'b1010

// -ve and +ve 10b symbols 
`define pK28_5_10b_symbol 10'b1100000101 // 0x305
`define nK28_5_10b_symbol 10'b0011111010 // 0x0fa

`define pD5_6_10b_symbol  10'b1010010110 // 0x296
`define nD5_6_10b_symbol  10'b1010010110 // 0x296
   
`define pD16_2_10b_symbol 10'b1001000101 // 0x245
`define nD16_2_10b_symbol 10'b0110110101 // 0x1b5

`define pD0_0_10b_symbol  10'b0110001011 // 0x18b
`define nD0_0_10b_symbol  10'b1001110100 // 0x274 

`define pK27_7_10b_symbol 10'b0010010111  // 0x097
`define nK27_7_10b_symbol 10'b1101101000  // 0x368

module ge_1000baseX_rx(
		       
   // Receive clock and reset 
   input               ck,
   input               reset,
		      
   // Receive 8B bus from 8b10 decoder 
   input [7:0] 	       ebi_rxd,	  
 
   input               ebi_K,
   input               rx_even,
   input               carrier_detect,
		   
   // Receive sync status 
   input              sync_status, 
   input              signal_detect,

   // Frame receive pulse	
   output              rx_frame_pulse,
	   
   // Receive GMII bus 
   output reg  [7:0]   gmii_rxd,
   output reg          gmii_rx_dv,  
   output reg          gmii_rx_er,
  
   output reg          receiving,

   // Auto-negotiation ctrl 
   input      [2:0]    xmit,
   output reg [15:0]   rx_config,
   output reg          rx_config_set,		   
   input               mr_main_reset,
   output reg [2:0]    rudi,

   output reg          ability_match,
   output reg          acknowledge_match,
		   
   output              consistency_match,
   output              idle_match
);
   
   //////////////////////////////////////////////////////////////////////////////
   //  Diagnostics registers
   //////////////////////////////////////////////////////////////////////////////
   
`define RX_FRAME_CNT            16'h0000
`define RX_DATA_CNT             16'h0001         
`define EARLY_END_CNT           16'h0002          
`define CHECK_END_T_R_K28_5_CNT 16'h0003
`define CHECK_END_R_R_K28_5_CNT 16'h0004
`define CHECK_END_T_R_R_CNT     16'h0005    
`define CHECK_END_R_R_R_CNT     16'h0006     
`define CHECK_END_R_R_S_CNT     16'h0007
`define RESET                   16'hffff 
   
   reg [7:0] 	       ge_x_pcs_rx_stats_inc;

   reg [15:0] 	       rx_frame_cnt;
   reg [15:0] 	       rx_data_cnt;
   reg [15:0] 	       early_end_cnt;
   reg [15:0] 	       check_end_T_R_K28_5_cnt;
   reg [15:0] 	       check_end_R_R_K28_5_cnt;
   reg [15:0] 	       check_end_T_R_R_cnt;
   reg [15:0] 	       check_end_R_R_R_cnt;
   reg [15:0] 	       check_end_R_R_S_cnt;
   
   always @(posedge ck or posedge reset)
     
     if (reset) 
       begin
	  rx_frame_cnt            <= 0; rx_data_cnt             <= 0;
	  early_end_cnt           <= 0; check_end_T_R_K28_5_cnt <= 0;
	  check_end_R_R_K28_5_cnt <= 0; check_end_T_R_R_cnt     <= 0;
	  check_end_R_R_R_cnt     <= 0; check_end_R_R_S_cnt     <= 0;
       end 
     else
       begin
	  if      (ge_x_pcs_rx_stats_inc[0]) rx_frame_cnt            <= rx_frame_cnt + 1;
	  else if (ge_x_pcs_rx_stats_inc[1]) rx_data_cnt             <= rx_data_cnt + 1;
	  else if (ge_x_pcs_rx_stats_inc[2]) early_end_cnt           <= early_end_cnt + 1;
	  else if (ge_x_pcs_rx_stats_inc[3]) check_end_T_R_K28_5_cnt <= check_end_T_R_K28_5_cnt + 1;
	  else if (ge_x_pcs_rx_stats_inc[4]) check_end_R_R_K28_5_cnt <= check_end_R_R_K28_5_cnt + 1;
	  else if (ge_x_pcs_rx_stats_inc[5]) check_end_T_R_R_cnt     <= check_end_T_R_R_cnt + 1;
	  else if (ge_x_pcs_rx_stats_inc[6]) check_end_R_R_R_cnt     <= check_end_R_R_R_cnt + 1;
	  else if (ge_x_pcs_rx_stats_inc[7]) check_end_R_R_S_cnt     <= check_end_R_R_S_cnt + 1;
       end

   //////////////////////////////////////////////////////////////////////////////
   //
   ////////////////////////////////////////////////////////////////////////////// 
   
   assign 	     rx_frame_pulse = ge_x_pcs_rx_stats_inc[0];
   
   //////////////////////////////////////////////////////////////////////////////
   // Soft reset
   //////////////////////////////////////////////////////////////////////////////  

   reg 		     soft_reset;
   
   always @(posedge ck or posedge reset)
     if (reset)
       soft_reset <= 0;
     else
       soft_reset <= mr_main_reset;

   //////////////////////////////////////////////////////////////////////////////
   // When Decoding EPDs (End_Of_Packet Delimiter) the RX state machine needs
   // to compare the current code-group to the two code-groups that follow it.
   //////////////////////////////////////////////////////////////////////////////   
  
   reg [7:0] 	       ebi_rxd_d1;
   reg [7:0] 	       ebi_rxd_d2;
   reg [7:0] 	       ebi_rxd_d3;
   
   reg 		       ebi_K_d1,          ebi_K_d2,          ebi_K_d3;  
   reg 		       rx_even_d1,        rx_even_d2,        rx_even_d3;
   reg 		       sync_status_d1,    sync_status_d2,    sync_status_d3; 		       
   reg 		       carrier_detect_d1, carrier_detect_d2, carrier_detect_d3;

   always @(posedge ck or posedge reset)
     if (reset)
       begin
	  ebi_K_d1          <= 0; ebi_K_d2          <= 0; ebi_K_d3          <= 0; 
	  rx_even_d1        <= 0; rx_even_d2        <= 0; rx_even_d3        <= 0;
	  ebi_rxd_d1        <= 0; ebi_rxd_d2        <= 0; ebi_rxd_d3        <= 0;
	  sync_status_d1    <= 0; sync_status_d2    <= 0; sync_status_d3    <= 0;
	  carrier_detect_d1 <= 0; carrier_detect_d2 <= 0; carrier_detect_d3 <= 0;
       end
     else
       begin 	  
	  ebi_K_d3          <= ebi_K_d2;           ebi_K_d2          <= ebi_K_d1;          ebi_K_d1          <= ebi_K; 
	  rx_even_d3        <= rx_even_d2;         rx_even_d2        <= rx_even_d1;        rx_even_d1        <= rx_even;
	  ebi_rxd_d3        <= ebi_rxd_d2;         ebi_rxd_d2        <= ebi_rxd_d1;        ebi_rxd_d1        <= ebi_rxd;
	  sync_status_d3    <= sync_status_d2;     sync_status_d2    <= sync_status_d1;    sync_status_d1    <= sync_status;
	  carrier_detect_d3 <= carrier_detect_d2;  carrier_detect_d2 <= carrier_detect_d1; carrier_detect_d1 <= carrier_detect;
       end
   

`ifdef MODEL_TECH
   wire [4:0] ebi_rxd_d1_X;  wire [2:0] ebi_rxd_d1_Y;
   wire [4:0] ebi_rxd_d2_X;  wire [2:0] ebi_rxd_d2_Y;
   wire [4:0] ebi_rxd_d3_X;  wire [2:0] ebi_rxd_d3_Y;

   assign {ebi_rxd_d1_Y, ebi_rxd_d1_X} = ebi_rxd_d1;
   assign {ebi_rxd_d2_Y, ebi_rxd_d2_X} = ebi_rxd_d2;
   assign {ebi_rxd_d3_Y, ebi_rxd_d3_X} = ebi_rxd_d3;
`endif    
   
   //////////////////////////////////////////////////////////////////////////////
   // Decode EARLY_END EPD code sequence
   //////////////////////////////////////////////////////////////////////////////   
  
   wire       early_end_idle;
   
   // Received code-group sequence K28.5/D/K28.5  
   assign     early_end_idle =  (ebi_K_d2  & ebi_rxd_d2 == `K28_5_symbol) & 
			       ~(ebi_K_d1) & 
			        (ebi_K     & ebi_rxd    == `K28_5_symbol);

   wire       early_end_config;
   
   // Received code-group sequence K28.5/(D21.5 | D2.2)/D0.0
   assign     early_end_config  = (( ebi_K_d2 &  ebi_rxd_d2  == `K28_5_symbol) & 
				   (~ebi_K_d1 & (ebi_rxd_d1  == `D21_5_symbol | ebi_rxd_d1 == `D2_2_symbol)) & 
				   (~ebi_K    &  ebi_rxd     == `D0_0_symbol));
   
   // EARLY_END state in 802.3-2008 Clause 36 Figure 36-7b
   reg 	      early_end;

   always @(posedge ck or posedge reset)
     if (reset)
       early_end <= 0;
     else
       early_end <= (early_end_idle | early_end_config) & rx_even;
   
   //////////////////////////////////////////////////////////////////////////////
   //  Decode /T/R/K28_5/ EPD code sequence
   //////////////////////////////////////////////////////////////////////////////   
 
   reg 	      check_end_T_R_K28_5;

   always @(posedge ck or posedge reset)
     if (reset)
       check_end_T_R_K28_5 <= 0;
     else 
       check_end_T_R_K28_5 <= ((ebi_K_d2 & ebi_rxd_d2  == `K29_7_symbol)  &
			       (ebi_K_d1 & ebi_rxd_d1  == `K23_7_symbol)  &
			       (ebi_K    & ebi_rxd     == `K28_5_symbol)  & rx_even);
   
   //////////////////////////////////////////////////////////////////////////////
   // Decode /T/R/R/ EPD code sequence
   //////////////////////////////////////////////////////////////////////////////  
  
   reg 	      check_end_T_R_R;
   
   always @(posedge ck or posedge reset)
     if (reset)
       check_end_T_R_R <= 0;
     else 
       check_end_T_R_R <= ((ebi_K_d2 & ebi_rxd_d2  == `K29_7_symbol) &
			   (ebi_K_d1 & ebi_rxd_d1  == `K23_7_symbol)  &
			   (ebi_K    & ebi_rxd     == `K23_7_symbol));
   
   //////////////////////////////////////////////////////////////////////////////
   // Decode /R/R/R EPD code sequence
   //////////////////////////////////////////////////////////////////////////////
   
   reg 	      check_end_R_R_R;
   
   always @(posedge ck or posedge reset)
     if (reset)
       check_end_R_R_R <= 0;
     else
       check_end_R_R_R <= ((ebi_K_d2 & ebi_rxd_d2 == `K23_7_symbol) &
			   (ebi_K_d1 & ebi_rxd_d1 == `K23_7_symbol) &
			   (ebi_K    & ebi_rxd    == `K23_7_symbol));
   
   //////////////////////////////////////////////////////////////////////////////
   // Decode /R/R/28_5 EPD code sequence
   //////////////////////////////////////////////////////////////////////////////
   
   reg 	      check_end_R_R_K28_5;
   
   always @(posedge ck or posedge reset)
     if (reset)
       check_end_R_R_K28_5 <= 0;
     else  
       check_end_R_R_K28_5 <= ((ebi_K_d2 & ebi_rxd_d2 == `K23_7_symbol) &
			       (ebi_K_d1 & ebi_rxd_d1 == `K23_7_symbol) &
			       (ebi_K    & ebi_rxd    == `K28_5_symbol) & rx_even);
   
   //////////////////////////////////////////////////////////////////////////////
   // Decode /R/R/S EPD code sequence
   ////////////////////////////////////////////////////////////////////////////// 
   
   reg   check_end_R_R_S;
   
   always @(posedge ck or posedge reset)
     if (reset)
       check_end_R_R_S <= 0;
     else
       check_end_R_R_S <= ((ebi_K_d2 & ebi_rxd_d2 == `K23_7_symbol) &
			   (ebi_K_d1 & ebi_rxd_d1 == `K23_7_symbol) &
			   (ebi_K & ebi_rxd == `K27_7_symbol));
   
   //////////////////////////////////////////////////////////////////////////////
   //  Dx.y and Kx.y symbol decoding 
   ////////////////////////////////////////////////////////////////////////////// 
   
   reg 	 K28_5_match, D2_2_match, D21_5_match, D5_6_match, D16_2_match;
   
   always @(posedge ck or posedge reset)
     if (reset)
       begin
	  K28_5_match <= 0;
	  D2_2_match  <= 0;
	  D21_5_match <= 0;
	  D5_6_match  <= 0;
	  D16_2_match <= 0;
       end
     else begin
	K28_5_match <= (ebi_K_d2 &  ebi_rxd_d2 == `K28_5_symbol);
	D2_2_match  <= ~ebi_K_d2 & (ebi_rxd_d2 == `D2_2_symbol);
	D21_5_match <= ~ebi_K_d2 & (ebi_rxd_d2 == `D21_5_symbol);
	D5_6_match  <= ~ebi_K_d2 & (ebi_rxd_d2 == `D5_6_symbol);
	D16_2_match <= ~ebi_K_d2 & (ebi_rxd_d2 == `D16_2_symbol);
     end
  
   //////////////////////////////////////////////////////////////////////////////
   // Start of packet (/S/), End of Packet (/T/) and Carrier Extend 
   // (/R/) symbol matching
   //////////////////////////////////////////////////////////////////////////////    
   
   reg     CE_match, SPD_match, EPD_match;
   
   always @(posedge ck or posedge reset)
     if (reset)
       begin
         CE_match   <= 0;
         SPD_match  <= 0;
         EPD_match  <= 0;
       end
     else
       begin
         CE_match   <= ebi_K_d2 & (ebi_rxd_d2 == `K23_7_symbol);
         SPD_match  <= ebi_K_d2 & (ebi_rxd_d2 == `K27_7_symbol);
         EPD_match  <= ebi_K_d2 & (ebi_rxd_d2 == `K29_7_symbol);
       end

   //////////////////////////////////////////////////////////////////////////////
   //
   ////////////////////////////////////////////////////////////////////////////// 
 
`ifdef MODEL_TECH
   
   wire [4:0] ebi_rxd_X;  wire [2:0] ebi_rxd_Y;
   
   assign     ebi_rxd_X = ebi_rxd[4:0];
   assign     ebi_rxd_Y = ebi_rxd[7:5];
`endif
   
   //////////////////////////////////////////////////////////////////////////////
   // rx_Config_reg
   //////////////////////////////////////////////////////////////////////////////  
 
   reg [15:0] rx_config_d1; reg [15:0] rx_config_d2;  reg [7:0] rx_config_lo;  
   
   reg 	      rx_config_lo_read, rx_config_hi_read;
   
   wire [15:0] rx_config_tmp = { ebi_rxd_d3, rx_config_lo };
   
   always @(posedge ck or posedge reset)
     if (reset)
       begin
	  rx_config <= 0; rx_config_set <= 0; rx_config_lo <= 0; rx_config_d1 <= 0; rx_config_d2 <= 0;
       end
     else
       begin
	  if (rx_config_lo_read) 
	    begin 
	       rx_config_d2  <= rx_config_d1; 
	       rx_config_d1  <= rx_config;
	       rx_config_lo  <= ebi_rxd_d3;
	    end
	  else if (rx_config_hi_read) begin
	     
	     rx_config  <= rx_config_tmp;
	     
	     rx_config_set <= |rx_config_tmp;
	  end
       end

   //////////////////////////////////////////////////////////////////////////////
   // rx_config_cnt
   ////////////////////////////////////////////////////////////////////////////// 
   
   reg [2:0] rx_config_cnt;
   reg 	     rx_config_cnt_m_inc, rx_config_cnt_m_rst;

   always @(posedge ck or posedge reset)
     if (reset)
       rx_config_cnt <= 0;
     else
       begin
   	  if      (rx_config_cnt_m_inc) rx_config_cnt <= rx_config_cnt + 1;
   	  else if (rx_config_cnt_m_rst) rx_config_cnt <= 0;
       end

   wire rx_config_cnt_done;

   assign rx_config_cnt_done = (rx_config_cnt == 3);
   
   //////////////////////////////////////////////////////////////////////////////
   // receive ability matching
   //////////////////////////////////////////////////////////////////////////////    
   
   wire [6:0] ability; wire [6:0] ability_d1; wire [6:0] ability_d2;
   
   assign      ability    = { rx_config[15],    rx_config[13:12],    rx_config[8:5]   };  
   assign      ability_d1 = { rx_config_d1[15], rx_config_d1[13:12], rx_config_d1[8:5]}; 
   assign      ability_d2 = { rx_config_d2[15], rx_config_d2[13:12], rx_config_d2[8:5]};     

   assign ability_matched1 = ~| (ability ^ ability_d1);
   assign ability_matched2 = ~| (ability ^ ability_d2);
   
   assign ability_matched = rx_config_cnt_done & ability_matched1 & ability_matched2;
   
     reg [6:0] ability_matched_reg;

   always @(posedge ck or posedge reset)
     if (reset)
       ability_matched_reg <= 0;
     else begin

	ability_match <= ability_matched;
	
	if (ability_matched) ability_matched_reg <= ability;
     end
 
   //////////////////////////////////////////////////////////////////////////////
   // receive config matching
   //////////////////////////////////////////////////////////////////////////////   
   
   assign rx_config_match1 = ability_matched1 & ~(rx_config[14] ^ rx_config_d1[14]);
   assign rx_config_match2 = ability_matched2 & ~(rx_config[14] ^ rx_config_d2[14]);
   
   assign  rx_config_match = rx_config_match1 & rx_config_match2;
   
   //////////////////////////////////////////////////////////////////////////////
   // receive acknowledge matching
   //////////////////////////////////////////////////////////////////////////////    
  
   always @(posedge ck or posedge reset)
     
     acknowledge_match <= (reset) ? 0 : ( rx_config_match & rx_config_d2[14] );

   //////////////////////////////////////////////////////////////////////////////
   // receive consistency matching
   ////////////////////////////////////////////////////////////////////////////// 

   assign        consistency_match = ability_match & ~|(ability_matched_reg ^ ability);
 
   //////////////////////////////////////////////////////////////////////////////
   // receive idle counter/matching
   ////////////////////////////////////////////////////////////////////////////// 
   
   reg [1:0]   idle_cnt;
   
   reg 	       idle_cnt_m_inc, idle_cnt_m_clr;
   
   always @(posedge ck or posedge reset)

      if (reset)
	   idle_cnt <= 0;
      else
	begin
	   if      (idle_cnt_m_clr) idle_cnt <= 0;
	   else if (idle_cnt_m_inc) idle_cnt <= idle_cnt + 1;
	end

   assign idle_match = (idle_cnt == 3);
   
   //////////////////////////////////////////////////////////////////////////////
   // RX_UNITDATA.indicate - Signal from PCS RX -> PCS AutoNeg process
   ////////////////////////////////////////////////////////////////////////////// 
  
   reg 	  rudi_INVALID_m_set; reg  rudi_IDLE_m_set; reg rudi_CONF_m_set;
   
   always @(posedge ck or posedge reset)
     if (reset)
       rudi <= `RUDI_INVALID;
     else
       begin
	  if      (rudi_INVALID_m_set)  rudi <= `RUDI_INVALID; 
	  else if (rudi_IDLE_m_set)     rudi <= `RUDI_IDLE;
	  else if (rudi_CONF_m_set)     rudi <= `RUDI_CONF;
       end

   //////////////////////////////////////////////////////////////////////////////
   // GMII output 
   ////////////////////////////////////////////////////////////////////////////// 
 
   reg gmii_rxd_false_carrier_m_set, gmii_rxd_preamble_m_set, gmii_rxd_ext_err_m_set;
   
   reg gmii_rxd_packet_burst_m_set, gmii_rxd_trr_extend_m_set, gmii_rxd_m_set;
   
   always @(posedge ck or posedge reset)
     
     if (reset)
       gmii_rxd <= 0;
     else
       begin
	  gmii_rxd <= (gmii_rxd_m_set)               ? ebi_rxd_d3  :
		      (gmii_rxd_false_carrier_m_set) ? 8'b00001110 :
		      (gmii_rxd_preamble_m_set)      ? 8'b01010101 :
		      (gmii_rxd_ext_err_m_set)       ? 8'b00011111 :
		      (gmii_rxd_trr_extend_m_set)    ? 8'b00001111 :
		      (gmii_rxd_packet_burst_m_set)  ? 8'b00001111 : 0;
       end 

   //////////////////////////////////////////////////////////////////////////////
   // Current receive state
   ////////////////////////////////////////////////////////////////////////////// 
  
   reg 	receiving_m_set, receiving_m_clr;
   
   always @(posedge ck or posedge reset)
     if (reset)
       receiving <= 0;
     else
       begin
	  if      (receiving_m_set) receiving <= 1;
	  else if (receiving_m_clr) receiving <= 0;
       end
     	 

`ifdef MODEL_TECH
  enum logic [4:0] {
`else
  localparam
`endif
		    S_PCS_RX_START            = 0,
		    S_PCS_RX_LINK_FAILED      = 1,
		    S_PCS_RX_WAIT_K           = 2,
		    S_PCS_RX_K                = 3,
		    S_PCS_RX_CONFIG_CB        = 4,
		    S_PCS_RX_CONFIG_CC        = 5,
		    S_PCS_RX_CONFIG_CD        = 6,
		    S_PCS_RX_INVALID          = 7,
		    S_PCS_RX_IDLE_D           = 8,
		    S_PCS_RX_FALSE_CARRIER    = 9,
		    S_PCS_RX_START_OF_PACKET  = 10,
		    S_PCS_RX_RECEIVE          = 11,
		    S_PCS_RX_EARLY_END        = 12,
		    S_PCS_RX_TRI_RRI          = 13,
		    S_PCS_RX_TRR_EXTEND       = 14,
		    S_PCS_RX_EPD2_CHECK_END   = 15,
		    S_PCS_RX_PACKET_BURST_RRS = 16,
		    S_PCS_RX_EXTEND_ERR       = 17,
		    S_PCS_RX_EARLY_END_EXT    = 18,
		    S_PCS_RX_DATA_ERROR       = 19,
		    S_PCS_RX_DATA             = 20
`ifdef MODEL_TECH
  } pcs_rx_present, pcs_rx_next;
`else
   ; reg [4:0] pcs_rx_present, pcs_rx_next;
`endif
   
   //////////////////////////////////////////////////////////////////////////////
   // gmii_rx_er ctrl
   //////////////////////////////////////////////////////////////////////////////

   reg gmii_rx_er_m_set, gmii_rx_er_m_clr;
   
   always @(posedge ck or posedge reset)
     if (reset)
       gmii_rx_er <= 0;
     else
       begin
	  if      (gmii_rx_er_m_set) gmii_rx_er <= 1;
	  else if (gmii_rx_er_m_clr) gmii_rx_er <= 0;
       end
   
   //////////////////////////////////////////////////////////////////////////////
   // gmii_rx_dv ctrl
   ////////////////////////////////////////////////////////////////////////////// 
   
   reg gmii_rx_dv_m_set, gmii_rx_dv_m_clr;
   
   always @(posedge ck or posedge reset)
     if (reset)
       gmii_rx_dv <= 0;
     else
       begin
	  if      (gmii_rx_dv_m_set) gmii_rx_dv <= 1;
	  else if (gmii_rx_dv_m_clr) gmii_rx_dv <= 0;
       end   

   //////////////////////////////////////////////////////////////////////////////
   // 
   ////////////////////////////////////////////////////////////////////////////// 
   
   wire  xmit_DATA, xmit_nDATA, xmit_DATA_CD, xmit_DATA_nCD;
   
   assign xmit_DATA = (xmit == `XMIT_DATA);
   
   assign xmit_nDATA = (xmit != `XMIT_DATA);
   
   assign xmit_DATA_CD = (xmit_DATA & carrier_detect_d3);
   
   assign xmit_DATA_nCD = (xmit_DATA & ~carrier_detect_d3);
 
   wire   xmit_DATA_CD_SPD, xmit_DATA_CD_nSPD, xmit_DATA_CD_nSPD_nK28_5;
   
   assign xmit_DATA_CD_SPD = xmit_DATA_CD & SPD_match;
   
   assign xmit_DATA_CD_nSPD = xmit_DATA_CD & ~SPD_match;
   
   assign xmit_DATA_CD_nSPD_nK28_5 = xmit_DATA_CD_nSPD & ~K28_5_match;


   //////////////////////////////////////////////////////////////////////////////
   // receive state machine registered part.
   //////////////////////////////////////////////////////////////////////////////    
     
   always @(posedge ck or posedge reset)
     
     pcs_rx_present <= (reset) ? S_PCS_RX_START :  pcs_rx_next;
    
   //////////////////////////////////////////////////////////////////////////////
   // receive state machine - IEEE 802.3-2008 Clause 36  Figure 36-7a, 36-7b
   ////////////////////////////////////////////////////////////////////////////// 

   always @*
     begin	
	pcs_rx_next = pcs_rx_present;

	rx_config_lo_read = 0; rx_config_hi_read = 0;
 	
	receiving_m_set = 0; receiving_m_clr = 0;
		
	gmii_rxd_false_carrier_m_set = 0; gmii_rxd_preamble_m_set = 0; gmii_rxd_ext_err_m_set = 0; 
	
	gmii_rxd_packet_burst_m_set = 0; gmii_rxd_trr_extend_m_set = 0; gmii_rxd_m_set = 0;
	
	idle_cnt_m_clr = 0; idle_cnt_m_inc = 0;
	
	gmii_rx_er_m_set = 0; gmii_rx_er_m_clr = 0;
	
	gmii_rx_dv_m_set = 0; gmii_rx_dv_m_clr = 0;
	
	rudi_INVALID_m_set = 0; rudi_IDLE_m_set = 0; rudi_CONF_m_set = 0;

	rx_config_cnt_m_inc = 0; rx_config_cnt_m_rst = 0;

	ge_x_pcs_rx_stats_inc = 16'h0000;
		
	case (pcs_rx_present)

	  S_PCS_RX_START:
	    begin
	       pcs_rx_next = S_PCS_RX_LINK_FAILED; 
	    end
	  
	  S_PCS_RX_LINK_FAILED:
	    begin
	       rudi_INVALID_m_set = (xmit_nDATA);
	       
	       if (receiving) begin receiving_m_clr = 1;  gmii_rx_er_m_set = 1; end
	       else           begin gmii_rx_dv_m_clr = 1; gmii_rx_er_m_clr = 1; end
	       
	       pcs_rx_next = S_PCS_RX_WAIT_K;
	    end
	  
	  S_PCS_RX_WAIT_K:
	    begin
	       rx_config_cnt_m_rst = 1;
	       
	       receiving_m_clr = 1; gmii_rx_dv_m_clr = 1; gmii_rx_er_m_clr = 1;

	       pcs_rx_next = (K28_5_match & rx_even_d3) ? S_PCS_RX_K : S_PCS_RX_WAIT_K;
	    end


	  S_PCS_RX_K:
	    begin
	       receiving_m_clr = 1; gmii_rx_dv_m_clr = 1; gmii_rx_er_m_clr = 1;

	       rudi_IDLE_m_set = (xmit_nDATA & ~ebi_K_d3 & ~D21_5_match & ~D2_2_match) |
				 (xmit_DATA & ~D21_5_match & ~D2_2_match);
              	       
	       pcs_rx_next = (D21_5_match | D2_2_match)                              ? S_PCS_RX_CONFIG_CB   :	 
			     ((xmit_nDATA) & ~ebi_K_d3 & ~D21_5_match & ~D2_2_match) ? S_PCS_RX_IDLE_D      :
			     ((xmit_DATA) & ~D21_5_match & ~D2_2_match)              ? S_PCS_RX_IDLE_D      :
                             ((xmit_nDATA) & ebi_K_d3)                               ? S_PCS_RX_INVALID     : S_PCS_RX_INVALID;
	    end
	  
	  S_PCS_RX_CONFIG_CB:
	    begin
	       // Keep a count of the number of consecutive /C/ streams 
	       rx_config_cnt_m_inc = ~rx_config_cnt_done;
	       
	       rx_config_lo_read = ~ebi_K_d3; 
	       
	       receiving_m_clr = 1; gmii_rx_dv_m_clr = 1; gmii_rx_er_m_clr = 1;
	       
	       pcs_rx_next = (ebi_K_d3) ? S_PCS_RX_INVALID : S_PCS_RX_CONFIG_CC;	     
	    end

	  
	  S_PCS_RX_CONFIG_CC:
	    begin
	       rx_config_hi_read = ~ebi_K_d3;  idle_cnt_m_clr = 1;
	       
	       // Signal from RX -> ANEG indicating /C/ ordered set received
	       rudi_CONF_m_set = ~ebi_K_d3; 

	       pcs_rx_next = (ebi_K_d3) ? S_PCS_RX_INVALID : S_PCS_RX_CONFIG_CD;
	    end

	  S_PCS_RX_CONFIG_CD:
	    begin
	       pcs_rx_next = (K28_5_match & rx_even_d3) ? S_PCS_RX_K : S_PCS_RX_INVALID;
	    end
	  
	  
	  S_PCS_RX_INVALID:
	    begin
	       // Signal from RX -> ANEG indicating INVALID
	       rudi_INVALID_m_set = (xmit == `XMIT_CONFIGURATION);
	       
	       receiving_m_set = (xmit_DATA);
	       
	       pcs_rx_next = (K28_5_match & rx_even_d3)  ? S_PCS_RX_K       :
			     (~K28_5_match & rx_even_d3) ? S_PCS_RX_WAIT_K  : S_PCS_RX_INVALID;
	    end

	  
	  S_PCS_RX_IDLE_D:
	    begin
	       // Must be receiving a IDLE so reset config cnt and idle_matcher logic
	       rx_config_cnt_m_rst = 1;  idle_cnt_m_inc = ~idle_match; 

	       // Signal from RX -> ANEG indicating /I/ ordered set received
	       rudi_IDLE_m_set = 1;
	       
	       // Generate rx_dv only if we've detected a START_OF_PACKET
	       if (xmit_DATA_CD_SPD)         gmii_rx_dv_m_set = 1; else gmii_rx_dv_m_clr = 1;

	       // Generate rx_er if we've detected a FALSE_CARRIER
	       if (xmit_DATA_CD_nSPD_nK28_5) gmii_rx_er_m_set = 1; else gmii_rx_er_m_clr = 1;
	       
	       if (xmit_DATA_CD) 
		 begin
		    if (~K28_5_match) 
		      begin 
			 receiving_m_set = 1;
			 if (SPD_match) gmii_rxd_preamble_m_set = 1; else gmii_rxd_false_carrier_m_set = 1;
		      end
		 end
	       else receiving_m_clr = 1; 

	       pcs_rx_next = (~K28_5_match & ~xmit_DATA    )  ? S_PCS_RX_INVALID       :
			     ( xmit_DATA_CD_SPD            )  ? S_PCS_RX_RECEIVE       : 
			     ( xmit_DATA_nCD | K28_5_match )  ? S_PCS_RX_K             :
			     ( xmit_DATA_CD_nSPD           )  ? S_PCS_RX_FALSE_CARRIER :  S_PCS_RX_IDLE_D;

	       ge_x_pcs_rx_stats_inc[0] = xmit_DATA_CD_SPD;
    
	    end 
	  
	  
	  S_PCS_RX_FALSE_CARRIER:
	    begin
	       gmii_rx_er_m_set = 1; gmii_rxd_false_carrier_m_set = 1;
	       
	       pcs_rx_next = (K28_5_match & rx_even_d3) ? S_PCS_RX_K : S_PCS_RX_FALSE_CARRIER;
	    end

	  //----------------------------------------------------------------------------
	  // IEEE 802.3-2008 Clause 36  Figure 36-7b

	  S_PCS_RX_START_OF_PACKET:
	    begin
	       gmii_rx_dv_m_set = 1; gmii_rx_er_m_clr = 1; gmii_rxd_preamble_m_set = 1;
	       
	       pcs_rx_next = S_PCS_RX_RECEIVE;
	    end
	  
	  S_PCS_RX_RECEIVE:
	    begin
	       
	       if (early_end)  // EARLY_END
		 begin
		    ge_x_pcs_rx_stats_inc[2] = 1;
		    
		    gmii_rx_er_m_set = 1; pcs_rx_next = S_PCS_RX_EARLY_END;
		 end

	       else if (check_end_T_R_K28_5) // TRI+RRI
		 begin
		    
		    ge_x_pcs_rx_stats_inc[3] = 1;
		    
		    receiving_m_clr = 1; gmii_rx_dv_m_clr  = 1;  gmii_rx_er_m_clr = 1;
		    
		    pcs_rx_next = S_PCS_RX_TRI_RRI;  
		 end

	       else if (check_end_T_R_R) // TRR+EXTEND
		 begin
		    
		    ge_x_pcs_rx_stats_inc[5] = 1;
   	    
		    gmii_rx_dv_m_clr  = 1;  gmii_rx_er_m_set = 1; gmii_rxd_trr_extend_m_set = 1;
		    
		    pcs_rx_next = S_PCS_RX_EPD2_CHECK_END; 
		 end
	       
	       else if (check_end_R_R_R) // EARLY_END_EXT
		 begin
		    
		    ge_x_pcs_rx_stats_inc[6] = 1;
		    
		    gmii_rx_er_m_set = 1;  pcs_rx_next = S_PCS_RX_EPD2_CHECK_END; 
		 end
	       
	       else if (~ebi_K_d3) // RX_DATA
		 begin
		    ge_x_pcs_rx_stats_inc[1] = 1;
		    
		    gmii_rx_er_m_clr = 1; gmii_rxd_m_set = 1;
		 end
	       
	       else  // RX_DATA_ERROR
		 gmii_rx_er_m_set = 1;
	    end

	  
	  S_PCS_RX_EARLY_END:
	    begin
	       pcs_rx_next =  (D21_5_match | D2_2_match) ? S_PCS_RX_CONFIG_CB : S_PCS_RX_IDLE_D;
	    end
	  
	  S_PCS_RX_TRI_RRI:
	    begin
	       pcs_rx_next = (K28_5_match) ? S_PCS_RX_K : S_PCS_RX_TRI_RRI;         
	    end
	    
	  S_PCS_RX_TRR_EXTEND:
	    begin
	       gmii_rx_dv_m_clr = 1; gmii_rx_er_m_set = 1; gmii_rxd_trr_extend_m_set = 1;
	       
	       pcs_rx_next = S_PCS_RX_EPD2_CHECK_END; 
	    end

	  
	  S_PCS_RX_EPD2_CHECK_END:
	    begin

	       if (check_end_R_R_R)
		 begin
		     
		    gmii_rx_dv_m_clr  = 1;  gmii_rx_er_m_set = 1; gmii_rxd_trr_extend_m_set = 1;
		 end

	       else if (check_end_R_R_K28_5)
		 begin
		    
		    ge_x_pcs_rx_stats_inc[4] = 1;
		    
		    receiving_m_clr = 1; gmii_rx_dv_m_clr = 1; gmii_rx_er_m_clr = 1;

		 end

	       else if (check_end_R_R_S)
		 begin
		    ge_x_pcs_rx_stats_inc[7] = 1;
		 end

	       pcs_rx_next = (check_end_R_R_R)     ? S_PCS_RX_TRR_EXTEND       :     
			     (check_end_R_R_K28_5) ? S_PCS_RX_TRI_RRI          :              
			     (check_end_R_R_S)     ? S_PCS_RX_PACKET_BURST_RRS : S_PCS_RX_EXTEND_ERR;       
	    end
	  
	  S_PCS_RX_PACKET_BURST_RRS:
	    begin
	       gmii_rx_dv_m_clr = 1; gmii_rxd_packet_burst_m_set = 1;
	       
	       pcs_rx_next = (SPD_match) ? S_PCS_RX_START_OF_PACKET : S_PCS_RX_PACKET_BURST_RRS;
	    end
	  
	   S_PCS_RX_EXTEND_ERR:
	     begin
		gmii_rx_dv_m_clr  = 1;  gmii_rxd_ext_err_m_set = 1;
		
		pcs_rx_next = (SPD_match)                              ? S_PCS_RX_START_OF_PACKET :
			      (K28_5_match & rx_even_d3)               ? S_PCS_RX_K           :          
			      (~SPD_match & ~K28_5_match & rx_even_d3) ? S_PCS_RX_EPD2_CHECK_END  : S_PCS_RX_EXTEND_ERR;
	     end
	  
	  S_PCS_RX_EARLY_END_EXT:
	    begin
	       gmii_rx_er_m_set = 1;
	         
	       pcs_rx_next = S_PCS_RX_EPD2_CHECK_END;  
	    end
	  
	  S_PCS_RX_DATA_ERROR:
	    begin 
	       gmii_rx_er_m_set = 1;
	       
	       pcs_rx_next = S_PCS_RX_RECEIVE;
	    end
	  
	  S_PCS_RX_DATA:
	    begin
	       gmii_rx_er_m_clr = 1; gmii_rxd_m_set = 1;
	       
	       pcs_rx_next = S_PCS_RX_RECEIVE;
	    end
	endcase

	if      (~signal_detect)  pcs_rx_next = S_PCS_RX_LINK_FAILED;
	else if (~sync_status_d3) pcs_rx_next = S_PCS_RX_LINK_FAILED;    
	else if (soft_reset)      pcs_rx_next = S_PCS_RX_WAIT_K;
	  
     end 
   
endmodule
"""

ge_1000baseX_rx ="""
//////////////////////////////////////////////////////////////////////
////                                                              ////
////  File name "ge_1000baseX_rx.v"                               ////
////                                                              ////
////  This file is part of the :                                  ////
////                                                              ////
//// "1000BASE-X IEEE 802.3-2008 Clause 36 - PCS project"         ////
////                                                              ////
////  http://opencores.org/project,1000base-x                     ////
////                                                              ////
////  Author(s):                                                  ////
////      - D.W.Pegler Cambridge Broadband Networks Ltd           ////
////                                                              ////
////      { peglerd@gmail.com, dwp@cambridgebroadand.com }        ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
////                                                              ////
//// Copyright (C) 2009 AUTHORS. All rights reserved.             ////
////                                                              ////
//// This source file may be used and distributed without         ////
//// restriction provided that this copyright statement is not    ////
//// removed from the file and that any derivative work contains  ////
//// the original copyright notice and the associated disclaimer. ////
////                                                              ////
//// This source file is free software; you can redistribute it   ////
//// and/or modify it under the terms of the GNU Lesser General   ////
//// Public License as published by the Free Software Foundation; ////
//// either version 2.1 of the License, or (at your option) any   ////
//// later version.                                               ////
////                                                              ////
//// This source is distributed in the hope that it will be       ////
//// useful, but WITHOUT ANY WARRANTY; without even the implied   ////
//// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      ////
//// PURPOSE.  See the GNU Lesser General Public License for more ////
//// details.                                                     ////
////                                                              ////
//// You should have received a copy of the GNU Lesser General    ////
//// Public License along with this source; if not, download it   ////
//// from http://www.opencores.org/lgpl.shtml                     ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
////                                                              ////
//// This module is based on the coding method described in       ////
//// IEEE Std 802.3-2008 Clause 36 "Physical Coding Sublayer(PCS) ////
//// and Physical Medium Attachment (PMA) sublayer, type          ////
//// 1000BASE-X"; see :                                           ////
////                                                              ////
//// http://standards.ieee.org/about/get/802/802.3.html           ////
//// and                                                          ////
//// doc/802.3-2008_section3.pdf, Clause/Section 36.              ////
////                                                              ////
//////////////////////////////////////////////////////////////////////

`define GMII_BASIC_CTRL   'd00
`define GMII_BASIC_STATUS 'd02
`define GMII_PHY_ID1      'd04
`define GMII_PHY_ID2      'd06
`define GMII_AN_ADV       'd08
`define GMII_AN_LP_ADV    'd10
`define GMII_AN_EXPANSION 'd12
`define GMII_AN_NP        'd14
`define GMII_AN_LP_NP     'd16

//////////////////////////////////////////////////////////////////////
////                                                              ////
////  File name "ge_1000baseX_regs.v"                             ////
////                                                              ////
////  This file is part of the :                                  ////
////                                                              ////
//// "1000BASE-X IEEE 802.3-2008 Clause 36 - PCS project"         ////
////                                                              ////
////  http://opencores.org/project,1000base-x                     ////
////                                                              ////
////  Author(s):                                                  ////
////      - D.W.Pegler Cambridge Broadband Networks Ltd           ////
////                                                              ////
////      { peglerd@gmail.com, dwp@cambridgebroadand.com }        ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
////                                                              ////
//// Copyright (C) 2009 AUTHORS. All rights reserved.             ////
////                                                              ////
//// This source file may be used and distributed without         ////
//// restriction provided that this copyright statement is not    ////
//// removed from the file and that any derivative work contains  ////
//// the original copyright notice and the associated disclaimer. ////
////                                                              ////
//// This source file is free software; you can redistribute it   ////
//// and/or modify it under the terms of the GNU Lesser General   ////
//// Public License as published by the Free Software Foundation; ////
//// either version 2.1 of the License, or (at your option) any   ////
//// later version.                                               ////
////                                                              ////
//// This source is distributed in the hope that it will be       ////
//// useful, but WITHOUT ANY WARRANTY; without even the implied   ////
//// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      ////
//// PURPOSE.  See the GNU Lesser General Public License for more ////
//// details.                                                     ////
////                                                              ////
//// You should have received a copy of the GNU Lesser General    ////
//// Public License along with this source; if not, download it   ////
//// from http://www.opencores.org/lgpl.shtml                     ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
////                                                              ////
//// This module is based on the coding method described in       ////
//// IEEE Std 802.3-2008 Clause 36 "Physical Coding Sublayer(PCS) ////
//// and Physical Medium Attachment (PMA) sublayer, type          ////
//// 1000BASE-X"; see :                                           ////
////                                                              ////
//// http://standards.ieee.org/about/get/802/802.3.html           ////
//// and                                                          ////
//// doc/802.3-2008_section3.pdf, Clause/Section 36.              ////
////                                                              ////
//////////////////////////////////////////////////////////////////////

`define GMII_BASIC_CTRL   'd00
`define GMII_BASIC_STATUS 'd02
`define GMII_PHY_ID1      'd04
`define GMII_PHY_ID2      'd06
`define GMII_AN_ADV       'd08
`define GMII_AN_LP_ADV    'd10
`define GMII_AN_EXPANSION 'd12
`define GMII_AN_NP        'd14
`define GMII_AN_LP_NP     'd16
// XMIT Autonegotiation parameter - ctrl for the PCS TX state machine   
`define XMIT_IDLE           0
`define XMIT_CONFIGURATION  1
`define XMIT_DATA           2
   
`define RUDI_INVALID 0
`define RUDI_IDLE    1
`define RUDI_CONF    2
   
// Special K code-groups - K codes
`define K28_0_symbol 8'h1c
`define K28_1_symbol 8'h3c
`define K28_2_symbol 8'h5c
`define K28_3_symbol 8'h7c
`define K28_4_symbol 8'h9c
`define K28_5_symbol 8'hbc
`define K28_6_symbol 8'hdc
`define K28_7_symbol 8'hfc
`define K23_7_symbol 8'hf7
`define K27_7_symbol 8'hfb
`define K29_7_symbol 8'hfd
`define K30_7_symbol 8'hfe

// Special D code-groups - D codes   
`define D21_5_symbol  8'hb5
`define D2_2_symbol   8'h42
`define D5_6_symbol   8'hc5
`define D16_2_symbol  8'h50
`define D0_0_symbol   8'h00

`define D21_2_symbol  8'h55
`define D21_6_symbol  8'hd5

`define D6_6_symbol   8'hc6
`define D10_1_symbol  8'h2a
`define D3_3_symbol   8'h63
`define D27_7_symbol  8'hfb
`define D3_0_symbol   8'h03

`define D30_2_symbol  8'h5e
`define D12_4_symbol  8'h8c
`define D8_6_symbol   8'hc8
`define D13_7_symbol  8'hed

// Code group ordered_sets
`define I_CODE  4'b0001
`define I1_CODE 4'b0010
`define I2_CODE 4'b0011
`define C_CODE  4'b0100
`define C1_CODE 4'b0101
`define C2_CODE 4'b0110
`define R_CODE  4'b0111
`define S_CODE  4'b1000
`define T_CODE  4'b1001
`define V_CODE  4'b1010

// -ve and +ve 10b symbols 
`define pK28_5_10b_symbol 10'b1100000101 // 0x305
`define nK28_5_10b_symbol 10'b0011111010 // 0x0fa

`define pD5_6_10b_symbol  10'b1010010110 // 0x296
`define nD5_6_10b_symbol  10'b1010010110 // 0x296
   
`define pD16_2_10b_symbol 10'b1001000101 // 0x245
`define nD16_2_10b_symbol 10'b0110110101 // 0x1b5

`define pD0_0_10b_symbol  10'b0110001011 // 0x18b
`define nD0_0_10b_symbol  10'b1001110100 // 0x274 

`define pK27_7_10b_symbol 10'b0010010111  // 0x097
`define nK27_7_10b_symbol 10'b1101101000  // 0x368

module  omsp_and_gate (

// OUTPUTs
    y,                         // AND gate output

// INPUTs
    a,                         // AND gate input A
    b                          // AND gate input B
);

// OUTPUTs
//=========
output         y;              // AND gate output

// INPUTs
//=========
input          a;              // AND gate input A
input          b;              // AND gate input B


//=============================================================================
// 1)  SOME COMMENTS ON THIS MODULE
//=============================================================================
//
//    In its ASIC version, some combinatorial pathes of the openMSP430 are
// sensitive to glitches, in particular the ones generating the wakeup
// signals.
//    To prevent synthesis from optmizing combinatorial clouds into glitchy
// logic, this AND gate module has been instanciated in the critical places.
//
//    Make sure that synthesis doesn't ungroup this module. As an alternative,
// a standard cell from the library could also be directly instanciated here
// (don't forget the "dont_touch" attribute)
//
//
//=============================================================================
// 2)  AND GATE
//=============================================================================

assign  y  =  a & b;

endmodule // omsp_and_gate

module  omsp_clock_gate (

// OUTPUTs
    gclk,                      // Gated clock

// INPUTs
    clk,                       // Clock
    enable,                    // Clock enable
    scan_enable                // Scan enable (active during scan shifting)
);

// OUTPUTs
//=========
output         gclk;           // Gated clock

// INPUTs
//=========
input          clk;            // Clock
input          enable;         // Clock enable
input          scan_enable;    // Scan enable (active during scan shifting)


//=============================================================================
// CLOCK GATE: LATCH + AND
//=============================================================================

// Enable clock gate during scan shift
// (the gate itself is checked with the scan capture cycle)
wire    enable_in =   (enable | scan_enable);

// LATCH the enable signal
reg     enable_latch;
always @(clk or enable_in)
  if (~clk)
    enable_latch <= enable_in;

// AND gate
assign  gclk      =  (clk & enable_latch);


endmodule // omsp_clock_gate


module ge_1000baseX_rx(
		       
   // Receive clock and reset 
   input               ck,
   input               reset,
		      
   // Receive 8B bus from 8b10 decoder 
   input [7:0] 	       ebi_rxd,	  
 
   input               ebi_K,
   input               rx_even,
   input               carrier_detect,
		   
   // Receive sync status 
   input              sync_status, 
   input              signal_detect,

   // Frame receive pulse	
   output              rx_frame_pulse,
	   
   // Receive GMII bus 
   output reg  [7:0]   gmii_rxd,
   output reg          gmii_rx_dv,  
   output reg          gmii_rx_er,
  
   output reg          receiving,

   // Auto-negotiation ctrl 
   input      [2:0]    xmit,
   output reg [15:0]   rx_config,
   output reg          rx_config_set,		   
   input               mr_main_reset,
   output reg [2:0]    rudi,

   output reg          ability_match,
   output reg          acknowledge_match,
		   
   output              consistency_match,
   output              idle_match
);
   
   //////////////////////////////////////////////////////////////////////////////
   //  Diagnostics registers
   //////////////////////////////////////////////////////////////////////////////
   
`define RX_FRAME_CNT            16'h0000
`define RX_DATA_CNT             16'h0001         
`define EARLY_END_CNT           16'h0002          
`define CHECK_END_T_R_K28_5_CNT 16'h0003
`define CHECK_END_R_R_K28_5_CNT 16'h0004
`define CHECK_END_T_R_R_CNT     16'h0005    
`define CHECK_END_R_R_R_CNT     16'h0006     
`define CHECK_END_R_R_S_CNT     16'h0007
`define RESET                   16'hffff 
   
   reg [7:0] 	       ge_x_pcs_rx_stats_inc;

   reg [15:0] 	       rx_frame_cnt;
   reg [15:0] 	       rx_data_cnt;
   reg [15:0] 	       early_end_cnt;
   reg [15:0] 	       check_end_T_R_K28_5_cnt;
   reg [15:0] 	       check_end_R_R_K28_5_cnt;
   reg [15:0] 	       check_end_T_R_R_cnt;
   reg [15:0] 	       check_end_R_R_R_cnt;
   reg [15:0] 	       check_end_R_R_S_cnt;
   
   always @(posedge ck or posedge reset)
     
     if (reset) 
       begin
	  rx_frame_cnt            <= 0; rx_data_cnt             <= 0;
	  early_end_cnt           <= 0; check_end_T_R_K28_5_cnt <= 0;
	  check_end_R_R_K28_5_cnt <= 0; check_end_T_R_R_cnt     <= 0;
	  check_end_R_R_R_cnt     <= 0; check_end_R_R_S_cnt     <= 0;
       end 
     else
       begin
	  if      (ge_x_pcs_rx_stats_inc[0]) rx_frame_cnt            <= rx_frame_cnt + 1;
	  else if (ge_x_pcs_rx_stats_inc[1]) rx_data_cnt             <= rx_data_cnt + 1;
	  else if (ge_x_pcs_rx_stats_inc[2]) early_end_cnt           <= early_end_cnt + 1;
	  else if (ge_x_pcs_rx_stats_inc[3]) check_end_T_R_K28_5_cnt <= check_end_T_R_K28_5_cnt + 1;
	  else if (ge_x_pcs_rx_stats_inc[4]) check_end_R_R_K28_5_cnt <= check_end_R_R_K28_5_cnt + 1;
	  else if (ge_x_pcs_rx_stats_inc[5]) check_end_T_R_R_cnt     <= check_end_T_R_R_cnt + 1;
	  else if (ge_x_pcs_rx_stats_inc[6]) check_end_R_R_R_cnt     <= check_end_R_R_R_cnt + 1;
	  else if (ge_x_pcs_rx_stats_inc[7]) check_end_R_R_S_cnt     <= check_end_R_R_S_cnt + 1;
       end

   //////////////////////////////////////////////////////////////////////////////
   //
   ////////////////////////////////////////////////////////////////////////////// 
   
   assign 	     rx_frame_pulse = ge_x_pcs_rx_stats_inc[0];
   
   //////////////////////////////////////////////////////////////////////////////
   // Soft reset
   //////////////////////////////////////////////////////////////////////////////  

   reg 		     soft_reset;
   
   always @(posedge ck or posedge reset)
     if (reset)
       soft_reset <= 0;
     else
       soft_reset <= mr_main_reset;

   //////////////////////////////////////////////////////////////////////////////
   // When Decoding EPDs (End_Of_Packet Delimiter) the RX state machine needs
   // to compare the current code-group to the two code-groups that follow it.
   //////////////////////////////////////////////////////////////////////////////   
  
   reg [7:0] 	       ebi_rxd_d1;
   reg [7:0] 	       ebi_rxd_d2;
   reg [7:0] 	       ebi_rxd_d3;
   
   reg 		       ebi_K_d1,          ebi_K_d2,          ebi_K_d3;  
   reg 		       rx_even_d1,        rx_even_d2,        rx_even_d3;
   reg 		       sync_status_d1,    sync_status_d2,    sync_status_d3; 		       
   reg 		       carrier_detect_d1, carrier_detect_d2, carrier_detect_d3;

   always @(posedge ck or posedge reset)
     if (reset)
       begin
	  ebi_K_d1          <= 0; ebi_K_d2          <= 0; ebi_K_d3          <= 0; 
	  rx_even_d1        <= 0; rx_even_d2        <= 0; rx_even_d3        <= 0;
	  ebi_rxd_d1        <= 0; ebi_rxd_d2        <= 0; ebi_rxd_d3        <= 0;
	  sync_status_d1    <= 0; sync_status_d2    <= 0; sync_status_d3    <= 0;
	  carrier_detect_d1 <= 0; carrier_detect_d2 <= 0; carrier_detect_d3 <= 0;
       end
     else
       begin 	  
	  ebi_K_d3          <= ebi_K_d2;           ebi_K_d2          <= ebi_K_d1;          ebi_K_d1          <= ebi_K; 
	  rx_even_d3        <= rx_even_d2;         rx_even_d2        <= rx_even_d1;        rx_even_d1        <= rx_even;
	  ebi_rxd_d3        <= ebi_rxd_d2;         ebi_rxd_d2        <= ebi_rxd_d1;        ebi_rxd_d1        <= ebi_rxd;
	  sync_status_d3    <= sync_status_d2;     sync_status_d2    <= sync_status_d1;    sync_status_d1    <= sync_status;
	  carrier_detect_d3 <= carrier_detect_d2;  carrier_detect_d2 <= carrier_detect_d1; carrier_detect_d1 <= carrier_detect;
       end
   

`ifdef MODEL_TECH
   wire [4:0] ebi_rxd_d1_X;  wire [2:0] ebi_rxd_d1_Y;
   wire [4:0] ebi_rxd_d2_X;  wire [2:0] ebi_rxd_d2_Y;
   wire [4:0] ebi_rxd_d3_X;  wire [2:0] ebi_rxd_d3_Y;

   assign {ebi_rxd_d1_Y, ebi_rxd_d1_X} = ebi_rxd_d1;
   assign {ebi_rxd_d2_Y, ebi_rxd_d2_X} = ebi_rxd_d2;
   assign {ebi_rxd_d3_Y, ebi_rxd_d3_X} = ebi_rxd_d3;
`endif    
   
   //////////////////////////////////////////////////////////////////////////////
   // Decode EARLY_END EPD code sequence
   //////////////////////////////////////////////////////////////////////////////   
  
   wire       early_end_idle;
   
   // Received code-group sequence K28.5/D/K28.5  
   assign     early_end_idle =  (ebi_K_d2  & ebi_rxd_d2 == `K28_5_symbol) & 
			       ~(ebi_K_d1) & 
			        (ebi_K     & ebi_rxd    == `K28_5_symbol);

   wire       early_end_config;
   
   // Received code-group sequence K28.5/(D21.5 | D2.2)/D0.0
   assign     early_end_config  = (( ebi_K_d2 &  ebi_rxd_d2  == `K28_5_symbol) & 
				   (~ebi_K_d1 & (ebi_rxd_d1  == `D21_5_symbol | ebi_rxd_d1 == `D2_2_symbol)) & 
				   (~ebi_K    &  ebi_rxd     == `D0_0_symbol));
   
   // EARLY_END state in 802.3-2008 Clause 36 Figure 36-7b
   reg 	      early_end;

   always @(posedge ck or posedge reset)
     if (reset)
       early_end <= 0;
     else
       early_end <= (early_end_idle | early_end_config) & rx_even;
   
   //////////////////////////////////////////////////////////////////////////////
   //  Decode /T/R/K28_5/ EPD code sequence
   //////////////////////////////////////////////////////////////////////////////   
 
   reg 	      check_end_T_R_K28_5;

   always @(posedge ck or posedge reset)
     if (reset)
       check_end_T_R_K28_5 <= 0;
     else 
       check_end_T_R_K28_5 <= ((ebi_K_d2 & ebi_rxd_d2  == `K29_7_symbol)  &
			       (ebi_K_d1 & ebi_rxd_d1  == `K23_7_symbol)  &
			       (ebi_K    & ebi_rxd     == `K28_5_symbol)  & rx_even);
   
   //////////////////////////////////////////////////////////////////////////////
   // Decode /T/R/R/ EPD code sequence
   //////////////////////////////////////////////////////////////////////////////  
  
   reg 	      check_end_T_R_R;
   
   always @(posedge ck or posedge reset)
     if (reset)
       check_end_T_R_R <= 0;
     else 
       check_end_T_R_R <= ((ebi_K_d2 & ebi_rxd_d2  == `K29_7_symbol) &
			   (ebi_K_d1 & ebi_rxd_d1  == `K23_7_symbol)  &
			   (ebi_K    & ebi_rxd     == `K23_7_symbol));
   
   //////////////////////////////////////////////////////////////////////////////
   // Decode /R/R/R EPD code sequence
   //////////////////////////////////////////////////////////////////////////////
   
   reg 	      check_end_R_R_R;
   
   always @(posedge ck or posedge reset)
     if (reset)
       check_end_R_R_R <= 0;
     else
       check_end_R_R_R <= ((ebi_K_d2 & ebi_rxd_d2 == `K23_7_symbol) &
			   (ebi_K_d1 & ebi_rxd_d1 == `K23_7_symbol) &
			   (ebi_K    & ebi_rxd    == `K23_7_symbol));
   
   //////////////////////////////////////////////////////////////////////////////
   // Decode /R/R/28_5 EPD code sequence
   //////////////////////////////////////////////////////////////////////////////
   
   reg 	      check_end_R_R_K28_5;
   
   always @(posedge ck or posedge reset)
     if (reset)
       check_end_R_R_K28_5 <= 0;
     else  
       check_end_R_R_K28_5 <= ((ebi_K_d2 & ebi_rxd_d2 == `K23_7_symbol) &
			       (ebi_K_d1 & ebi_rxd_d1 == `K23_7_symbol) &
			       (ebi_K    & ebi_rxd    == `K28_5_symbol) & rx_even);
   
   //////////////////////////////////////////////////////////////////////////////
   // Decode /R/R/S EPD code sequence
   ////////////////////////////////////////////////////////////////////////////// 
   
   reg   check_end_R_R_S;
   
   always @(posedge ck or posedge reset)
     if (reset)
       check_end_R_R_S <= 0;
     else
       check_end_R_R_S <= ((ebi_K_d2 & ebi_rxd_d2 == `K23_7_symbol) &
			   (ebi_K_d1 & ebi_rxd_d1 == `K23_7_symbol) &
			   (ebi_K & ebi_rxd == `K27_7_symbol));
   
   //////////////////////////////////////////////////////////////////////////////
   //  Dx.y and Kx.y symbol decoding 
   ////////////////////////////////////////////////////////////////////////////// 
   
   reg 	 K28_5_match, D2_2_match, D21_5_match, D5_6_match, D16_2_match;
   
   always @(posedge ck or posedge reset)
     if (reset)
       begin
	  K28_5_match <= 0;
	  D2_2_match  <= 0;
	  D21_5_match <= 0;
	  D5_6_match  <= 0;
	  D16_2_match <= 0;
       end
     else begin
	K28_5_match <= (ebi_K_d2 &  ebi_rxd_d2 == `K28_5_symbol);
	D2_2_match  <= ~ebi_K_d2 & (ebi_rxd_d2 == `D2_2_symbol);
	D21_5_match <= ~ebi_K_d2 & (ebi_rxd_d2 == `D21_5_symbol);
	D5_6_match  <= ~ebi_K_d2 & (ebi_rxd_d2 == `D5_6_symbol);
	D16_2_match <= ~ebi_K_d2 & (ebi_rxd_d2 == `D16_2_symbol);
     end
  
   //////////////////////////////////////////////////////////////////////////////
   // Start of packet (/S/), End of Packet (/T/) and Carrier Extend 
   // (/R/) symbol matching
   //////////////////////////////////////////////////////////////////////////////    
   
   reg     CE_match, SPD_match, EPD_match;
   
   always @(posedge ck or posedge reset)
     if (reset)
       begin
         CE_match   <= 0;
         SPD_match  <= 0;
         EPD_match  <= 0;
       end
     else
       begin
         CE_match   <= ebi_K_d2 & (ebi_rxd_d2 == `K23_7_symbol);
         SPD_match  <= ebi_K_d2 & (ebi_rxd_d2 == `K27_7_symbol);
         EPD_match  <= ebi_K_d2 & (ebi_rxd_d2 == `K29_7_symbol);
       end

   //////////////////////////////////////////////////////////////////////////////
   //
   ////////////////////////////////////////////////////////////////////////////// 
 
`ifdef MODEL_TECH
   
   wire [4:0] ebi_rxd_X;  wire [2:0] ebi_rxd_Y;
   
   assign     ebi_rxd_X = ebi_rxd[4:0];
   assign     ebi_rxd_Y = ebi_rxd[7:5];
`endif
   
   //////////////////////////////////////////////////////////////////////////////
   // rx_Config_reg
   //////////////////////////////////////////////////////////////////////////////  
 
   reg [15:0] rx_config_d1; reg [15:0] rx_config_d2;  reg [7:0] rx_config_lo;  
   
   reg 	      rx_config_lo_read, rx_config_hi_read;
   
   wire [15:0] rx_config_tmp = { ebi_rxd_d3, rx_config_lo };
   
   always @(posedge ck or posedge reset)
     if (reset)
       begin
	  rx_config <= 0; rx_config_set <= 0; rx_config_lo <= 0; rx_config_d1 <= 0; rx_config_d2 <= 0;
       end
     else
       begin
	  if (rx_config_lo_read) 
	    begin 
	       rx_config_d2  <= rx_config_d1; 
	       rx_config_d1  <= rx_config;
	       rx_config_lo  <= ebi_rxd_d3;
	    end
	  else if (rx_config_hi_read) begin
	     
	     rx_config  <= rx_config_tmp;
	     
	     rx_config_set <= |rx_config_tmp;
	  end
       end

   //////////////////////////////////////////////////////////////////////////////
   // rx_config_cnt
   ////////////////////////////////////////////////////////////////////////////// 
   
   reg [2:0] rx_config_cnt;
   reg 	     rx_config_cnt_m_inc, rx_config_cnt_m_rst;

   always @(posedge ck or posedge reset)
     if (reset)
       rx_config_cnt <= 0;
     else
       begin
   	  if      (rx_config_cnt_m_inc) rx_config_cnt <= rx_config_cnt + 1;
   	  else if (rx_config_cnt_m_rst) rx_config_cnt <= 0;
       end

   wire rx_config_cnt_done;

   assign rx_config_cnt_done = (rx_config_cnt == 3);
   
   //////////////////////////////////////////////////////////////////////////////
   // receive ability matching
   //////////////////////////////////////////////////////////////////////////////    
   
   wire [6:0] ability; wire [6:0] ability_d1; wire [6:0] ability_d2;
   
   assign      ability    = { rx_config[15],    rx_config[13:12],    rx_config[8:5]   };  
   assign      ability_d1 = { rx_config_d1[15], rx_config_d1[13:12], rx_config_d1[8:5]}; 
   assign      ability_d2 = { rx_config_d2[15], rx_config_d2[13:12], rx_config_d2[8:5]};     

   assign ability_matched1 = ~| (ability ^ ability_d1);
   assign ability_matched2 = ~| (ability ^ ability_d2);
   
   assign ability_matched = rx_config_cnt_done & ability_matched1 & ability_matched2;
   
     reg [6:0] ability_matched_reg;

   always @(posedge ck or posedge reset)
     if (reset)
       ability_matched_reg <= 0;
     else begin

	ability_match <= ability_matched;
	
	if (ability_matched) ability_matched_reg <= ability;
     end
 
   //////////////////////////////////////////////////////////////////////////////
   // receive config matching
   //////////////////////////////////////////////////////////////////////////////   
   
   assign rx_config_match1 = ability_matched1 & ~(rx_config[14] ^ rx_config_d1[14]);
   assign rx_config_match2 = ability_matched2 & ~(rx_config[14] ^ rx_config_d2[14]);
   
   assign  rx_config_match = rx_config_match1 & rx_config_match2;
   
   //////////////////////////////////////////////////////////////////////////////
   // receive acknowledge matching
   //////////////////////////////////////////////////////////////////////////////    
  
   always @(posedge ck or posedge reset)
     
     acknowledge_match <= (reset) ? 0 : ( rx_config_match & rx_config_d2[14] );

   //////////////////////////////////////////////////////////////////////////////
   // receive consistency matching
   ////////////////////////////////////////////////////////////////////////////// 

   assign        consistency_match = ability_match & ~|(ability_matched_reg ^ ability);
 
   //////////////////////////////////////////////////////////////////////////////
   // receive idle counter/matching
   ////////////////////////////////////////////////////////////////////////////// 
   
   reg [1:0]   idle_cnt;
   
   reg 	       idle_cnt_m_inc, idle_cnt_m_clr;
   
   always @(posedge ck or posedge reset)

      if (reset)
	   idle_cnt <= 0;
      else
	begin
	   if      (idle_cnt_m_clr) idle_cnt <= 0;
	   else if (idle_cnt_m_inc) idle_cnt <= idle_cnt + 1;
	end

   assign idle_match = (idle_cnt == 3);
   
   //////////////////////////////////////////////////////////////////////////////
   // RX_UNITDATA.indicate - Signal from PCS RX -> PCS AutoNeg process
   ////////////////////////////////////////////////////////////////////////////// 
  
   reg 	  rudi_INVALID_m_set; reg  rudi_IDLE_m_set; reg rudi_CONF_m_set;
   
   always @(posedge ck or posedge reset)
     if (reset)
       rudi <= `RUDI_INVALID;
     else
       begin
	  if      (rudi_INVALID_m_set)  rudi <= `RUDI_INVALID; 
	  else if (rudi_IDLE_m_set)     rudi <= `RUDI_IDLE;
	  else if (rudi_CONF_m_set)     rudi <= `RUDI_CONF;
       end

   //////////////////////////////////////////////////////////////////////////////
   // GMII output 
   ////////////////////////////////////////////////////////////////////////////// 
 
   reg gmii_rxd_false_carrier_m_set, gmii_rxd_preamble_m_set, gmii_rxd_ext_err_m_set;
   
   reg gmii_rxd_packet_burst_m_set, gmii_rxd_trr_extend_m_set, gmii_rxd_m_set;
   
   always @(posedge ck or posedge reset)
     
     if (reset)
       gmii_rxd <= 0;
     else
       begin
	  gmii_rxd <= (gmii_rxd_m_set)               ? ebi_rxd_d3  :
		      (gmii_rxd_false_carrier_m_set) ? 8'b00001110 :
		      (gmii_rxd_preamble_m_set)      ? 8'b01010101 :
		      (gmii_rxd_ext_err_m_set)       ? 8'b00011111 :
		      (gmii_rxd_trr_extend_m_set)    ? 8'b00001111 :
		      (gmii_rxd_packet_burst_m_set)  ? 8'b00001111 : 0;
       end 

   //////////////////////////////////////////////////////////////////////////////
   // Current receive state
   ////////////////////////////////////////////////////////////////////////////// 
  
   reg 	receiving_m_set, receiving_m_clr;
   
   always @(posedge ck or posedge reset)
     if (reset)
       receiving <= 0;
     else
       begin
	  if      (receiving_m_set) receiving <= 1;
	  else if (receiving_m_clr) receiving <= 0;
       end
     	 

`ifdef MODEL_TECH
  enum logic [4:0] {
`else
  localparam
`endif
		    S_PCS_RX_START            = 0,
		    S_PCS_RX_LINK_FAILED      = 1,
		    S_PCS_RX_WAIT_K           = 2,
		    S_PCS_RX_K                = 3,
		    S_PCS_RX_CONFIG_CB        = 4,
		    S_PCS_RX_CONFIG_CC        = 5,
		    S_PCS_RX_CONFIG_CD        = 6,
		    S_PCS_RX_INVALID          = 7,
		    S_PCS_RX_IDLE_D           = 8,
		    S_PCS_RX_FALSE_CARRIER    = 9,
		    S_PCS_RX_START_OF_PACKET  = 10,
		    S_PCS_RX_RECEIVE          = 11,
		    S_PCS_RX_EARLY_END        = 12,
		    S_PCS_RX_TRI_RRI          = 13,
		    S_PCS_RX_TRR_EXTEND       = 14,
		    S_PCS_RX_EPD2_CHECK_END   = 15,
		    S_PCS_RX_PACKET_BURST_RRS = 16,
		    S_PCS_RX_EXTEND_ERR       = 17,
		    S_PCS_RX_EARLY_END_EXT    = 18,
		    S_PCS_RX_DATA_ERROR       = 19,
		    S_PCS_RX_DATA             = 20
`ifdef MODEL_TECH
  } pcs_rx_present, pcs_rx_next;
`else
   ; reg [4:0] pcs_rx_present, pcs_rx_next;
`endif
   
   //////////////////////////////////////////////////////////////////////////////
   // gmii_rx_er ctrl
   //////////////////////////////////////////////////////////////////////////////

   reg gmii_rx_er_m_set, gmii_rx_er_m_clr;
   
   always @(posedge ck or posedge reset)
     if (reset)
       gmii_rx_er <= 0;
     else
       begin
	  if      (gmii_rx_er_m_set) gmii_rx_er <= 1;
	  else if (gmii_rx_er_m_clr) gmii_rx_er <= 0;
       end
   
   //////////////////////////////////////////////////////////////////////////////
   // gmii_rx_dv ctrl
   ////////////////////////////////////////////////////////////////////////////// 
   
   reg gmii_rx_dv_m_set, gmii_rx_dv_m_clr;
   
   always @(posedge ck or posedge reset)
     if (reset)
       gmii_rx_dv <= 0;
     else
       begin
	  if      (gmii_rx_dv_m_set) gmii_rx_dv <= 1;
	  else if (gmii_rx_dv_m_clr) gmii_rx_dv <= 0;
       end   

   //////////////////////////////////////////////////////////////////////////////
   // 
   ////////////////////////////////////////////////////////////////////////////// 
   
   wire  xmit_DATA, xmit_nDATA, xmit_DATA_CD, xmit_DATA_nCD;
   
   assign xmit_DATA = (xmit == `XMIT_DATA);
   
   assign xmit_nDATA = (xmit != `XMIT_DATA);
   
   assign xmit_DATA_CD = (xmit_DATA & carrier_detect_d3);
   
   assign xmit_DATA_nCD = (xmit_DATA & ~carrier_detect_d3);
 
   wire   xmit_DATA_CD_SPD, xmit_DATA_CD_nSPD, xmit_DATA_CD_nSPD_nK28_5;
   
   assign xmit_DATA_CD_SPD = xmit_DATA_CD & SPD_match;
   
   assign xmit_DATA_CD_nSPD = xmit_DATA_CD & ~SPD_match;
   
   assign xmit_DATA_CD_nSPD_nK28_5 = xmit_DATA_CD_nSPD & ~K28_5_match;


   //////////////////////////////////////////////////////////////////////////////
   // receive state machine registered part.
   //////////////////////////////////////////////////////////////////////////////    
     
   always @(posedge ck or posedge reset)
     
     pcs_rx_present <= (reset) ? S_PCS_RX_START :  pcs_rx_next;
    
   //////////////////////////////////////////////////////////////////////////////
   // receive state machine - IEEE 802.3-2008 Clause 36  Figure 36-7a, 36-7b
   ////////////////////////////////////////////////////////////////////////////// 

   always @*
     begin	
	pcs_rx_next = pcs_rx_present;

	rx_config_lo_read = 0; rx_config_hi_read = 0;
 	
	receiving_m_set = 0; receiving_m_clr = 0;
		
	gmii_rxd_false_carrier_m_set = 0; gmii_rxd_preamble_m_set = 0; gmii_rxd_ext_err_m_set = 0; 
	
	gmii_rxd_packet_burst_m_set = 0; gmii_rxd_trr_extend_m_set = 0; gmii_rxd_m_set = 0;
	
	idle_cnt_m_clr = 0; idle_cnt_m_inc = 0;
	
	gmii_rx_er_m_set = 0; gmii_rx_er_m_clr = 0;
	
	gmii_rx_dv_m_set = 0; gmii_rx_dv_m_clr = 0;
	
	rudi_INVALID_m_set = 0; rudi_IDLE_m_set = 0; rudi_CONF_m_set = 0;

	rx_config_cnt_m_inc = 0; rx_config_cnt_m_rst = 0;

	ge_x_pcs_rx_stats_inc = 16'h0000;
		
	case (pcs_rx_present)

	  S_PCS_RX_START:
	    begin
	       pcs_rx_next = S_PCS_RX_LINK_FAILED; 
	    end
	  
	  S_PCS_RX_LINK_FAILED:
	    begin
	       rudi_INVALID_m_set = (xmit_nDATA);
	       
	       if (receiving) begin receiving_m_clr = 1;  gmii_rx_er_m_set = 1; end
	       else           begin gmii_rx_dv_m_clr = 1; gmii_rx_er_m_clr = 1; end
	       
	       pcs_rx_next = S_PCS_RX_WAIT_K;
	    end
	  
	  S_PCS_RX_WAIT_K:
	    begin
	       rx_config_cnt_m_rst = 1;
	       
	       receiving_m_clr = 1; gmii_rx_dv_m_clr = 1; gmii_rx_er_m_clr = 1;

	       pcs_rx_next = (K28_5_match & rx_even_d3) ? S_PCS_RX_K : S_PCS_RX_WAIT_K;
	    end


	  S_PCS_RX_K:
	    begin
	       receiving_m_clr = 1; gmii_rx_dv_m_clr = 1; gmii_rx_er_m_clr = 1;

	       rudi_IDLE_m_set = (xmit_nDATA & ~ebi_K_d3 & ~D21_5_match & ~D2_2_match) |
				 (xmit_DATA & ~D21_5_match & ~D2_2_match);
              	       
	       pcs_rx_next = (D21_5_match | D2_2_match)                              ? S_PCS_RX_CONFIG_CB   :	 
			     ((xmit_nDATA) & ~ebi_K_d3 & ~D21_5_match & ~D2_2_match) ? S_PCS_RX_IDLE_D      :
			     ((xmit_DATA) & ~D21_5_match & ~D2_2_match)              ? S_PCS_RX_IDLE_D      :
                             ((xmit_nDATA) & ebi_K_d3)                               ? S_PCS_RX_INVALID     : S_PCS_RX_INVALID;
	    end
	  
	  S_PCS_RX_CONFIG_CB:
	    begin
	       // Keep a count of the number of consecutive /C/ streams 
	       rx_config_cnt_m_inc = ~rx_config_cnt_done;
	       
	       rx_config_lo_read = ~ebi_K_d3; 
	       
	       receiving_m_clr = 1; gmii_rx_dv_m_clr = 1; gmii_rx_er_m_clr = 1;
	       
	       pcs_rx_next = (ebi_K_d3) ? S_PCS_RX_INVALID : S_PCS_RX_CONFIG_CC;	     
	    end

	  
	  S_PCS_RX_CONFIG_CC:
	    begin
	       rx_config_hi_read = ~ebi_K_d3;  idle_cnt_m_clr = 1;
	       
	       // Signal from RX -> ANEG indicating /C/ ordered set received
	       rudi_CONF_m_set = ~ebi_K_d3; 

	       pcs_rx_next = (ebi_K_d3) ? S_PCS_RX_INVALID : S_PCS_RX_CONFIG_CD;
	    end

	  S_PCS_RX_CONFIG_CD:
	    begin
	       pcs_rx_next = (K28_5_match & rx_even_d3) ? S_PCS_RX_K : S_PCS_RX_INVALID;
	    end
	  
	  
	  S_PCS_RX_INVALID:
	    begin
	       // Signal from RX -> ANEG indicating INVALID
	       rudi_INVALID_m_set = (xmit == `XMIT_CONFIGURATION);
	       
	       receiving_m_set = (xmit_DATA);
	       
	       pcs_rx_next = (K28_5_match & rx_even_d3)  ? S_PCS_RX_K       :
			     (~K28_5_match & rx_even_d3) ? S_PCS_RX_WAIT_K  : S_PCS_RX_INVALID;
	    end

	  
	  S_PCS_RX_IDLE_D:
	    begin
	       // Must be receiving a IDLE so reset config cnt and idle_matcher logic
	       rx_config_cnt_m_rst = 1;  idle_cnt_m_inc = ~idle_match; 

	       // Signal from RX -> ANEG indicating /I/ ordered set received
	       rudi_IDLE_m_set = 1;
	       
	       // Generate rx_dv only if we've detected a START_OF_PACKET
	       if (xmit_DATA_CD_SPD)         gmii_rx_dv_m_set = 1; else gmii_rx_dv_m_clr = 1;

	       // Generate rx_er if we've detected a FALSE_CARRIER
	       if (xmit_DATA_CD_nSPD_nK28_5) gmii_rx_er_m_set = 1; else gmii_rx_er_m_clr = 1;
	       
	       if (xmit_DATA_CD) 
		 begin
		    if (~K28_5_match) 
		      begin 
			 receiving_m_set = 1;
			 if (SPD_match) gmii_rxd_preamble_m_set = 1; else gmii_rxd_false_carrier_m_set = 1;
		      end
		 end
	       else receiving_m_clr = 1; 

	       pcs_rx_next = (~K28_5_match & ~xmit_DATA    )  ? S_PCS_RX_INVALID       :
			     ( xmit_DATA_CD_SPD            )  ? S_PCS_RX_RECEIVE       : 
			     ( xmit_DATA_nCD | K28_5_match )  ? S_PCS_RX_K             :
			     ( xmit_DATA_CD_nSPD           )  ? S_PCS_RX_FALSE_CARRIER :  S_PCS_RX_IDLE_D;

	       ge_x_pcs_rx_stats_inc[0] = xmit_DATA_CD_SPD;
    
	    end 
	  
	  
	  S_PCS_RX_FALSE_CARRIER:
	    begin
	       gmii_rx_er_m_set = 1; gmii_rxd_false_carrier_m_set = 1;
	       
	       pcs_rx_next = (K28_5_match & rx_even_d3) ? S_PCS_RX_K : S_PCS_RX_FALSE_CARRIER;
	    end

	  //----------------------------------------------------------------------------
	  // IEEE 802.3-2008 Clause 36  Figure 36-7b

	  S_PCS_RX_START_OF_PACKET:
	    begin
	       gmii_rx_dv_m_set = 1; gmii_rx_er_m_clr = 1; gmii_rxd_preamble_m_set = 1;
	       
	       pcs_rx_next = S_PCS_RX_RECEIVE;
	    end
	  
	  S_PCS_RX_RECEIVE:
	    begin
	       
	       if (early_end)  // EARLY_END
		 begin
		    ge_x_pcs_rx_stats_inc[2] = 1;
		    
		    gmii_rx_er_m_set = 1; pcs_rx_next = S_PCS_RX_EARLY_END;
		 end

	       else if (check_end_T_R_K28_5) // TRI+RRI
		 begin
		    
		    ge_x_pcs_rx_stats_inc[3] = 1;
		    
		    receiving_m_clr = 1; gmii_rx_dv_m_clr  = 1;  gmii_rx_er_m_clr = 1;
		    
		    pcs_rx_next = S_PCS_RX_TRI_RRI;  
		 end

	       else if (check_end_T_R_R) // TRR+EXTEND
		 begin
		    
		    ge_x_pcs_rx_stats_inc[5] = 1;
   	    
		    gmii_rx_dv_m_clr  = 1;  gmii_rx_er_m_set = 1; gmii_rxd_trr_extend_m_set = 1;
		    
		    pcs_rx_next = S_PCS_RX_EPD2_CHECK_END; 
		 end
	       
	       else if (check_end_R_R_R) // EARLY_END_EXT
		 begin
		    
		    ge_x_pcs_rx_stats_inc[6] = 1;
		    
		    gmii_rx_er_m_set = 1;  pcs_rx_next = S_PCS_RX_EPD2_CHECK_END; 
		 end
	       
	       else if (~ebi_K_d3) // RX_DATA
		 begin
		    ge_x_pcs_rx_stats_inc[1] = 1;
		    
		    gmii_rx_er_m_clr = 1; gmii_rxd_m_set = 1;
		 end
	       
	       else  // RX_DATA_ERROR
		 gmii_rx_er_m_set = 1;
	    end

	  
	  S_PCS_RX_EARLY_END:
	    begin
	       pcs_rx_next =  (D21_5_match | D2_2_match) ? S_PCS_RX_CONFIG_CB : S_PCS_RX_IDLE_D;
	    end
	  
	  S_PCS_RX_TRI_RRI:
	    begin
	       pcs_rx_next = (K28_5_match) ? S_PCS_RX_K : S_PCS_RX_TRI_RRI;         
	    end
	    
	  S_PCS_RX_TRR_EXTEND:
	    begin
	       gmii_rx_dv_m_clr = 1; gmii_rx_er_m_set = 1; gmii_rxd_trr_extend_m_set = 1;
	       
	       pcs_rx_next = S_PCS_RX_EPD2_CHECK_END; 
	    end

	  
	  S_PCS_RX_EPD2_CHECK_END:
	    begin

	       if (check_end_R_R_R)
		 begin
		     
		    gmii_rx_dv_m_clr  = 1;  gmii_rx_er_m_set = 1; gmii_rxd_trr_extend_m_set = 1;
		 end

	       else if (check_end_R_R_K28_5)
		 begin
		    
		    ge_x_pcs_rx_stats_inc[4] = 1;
		    
		    receiving_m_clr = 1; gmii_rx_dv_m_clr = 1; gmii_rx_er_m_clr = 1;

		 end

	       else if (check_end_R_R_S)
		 begin
		    ge_x_pcs_rx_stats_inc[7] = 1;
		 end

	       pcs_rx_next = (check_end_R_R_R)     ? S_PCS_RX_TRR_EXTEND       :     
			     (check_end_R_R_K28_5) ? S_PCS_RX_TRI_RRI          :              
			     (check_end_R_R_S)     ? S_PCS_RX_PACKET_BURST_RRS : S_PCS_RX_EXTEND_ERR;       
	    end
	  
	  S_PCS_RX_PACKET_BURST_RRS:
	    begin
	       gmii_rx_dv_m_clr = 1; gmii_rxd_packet_burst_m_set = 1;
	       
	       pcs_rx_next = (SPD_match) ? S_PCS_RX_START_OF_PACKET : S_PCS_RX_PACKET_BURST_RRS;
	    end
	  
	   S_PCS_RX_EXTEND_ERR:
	     begin
		gmii_rx_dv_m_clr  = 1;  gmii_rxd_ext_err_m_set = 1;
		
		pcs_rx_next = (SPD_match)                              ? S_PCS_RX_START_OF_PACKET :
			      (K28_5_match & rx_even_d3)               ? S_PCS_RX_K           :          
			      (~SPD_match & ~K28_5_match & rx_even_d3) ? S_PCS_RX_EPD2_CHECK_END  : S_PCS_RX_EXTEND_ERR;
	     end
	  
	  S_PCS_RX_EARLY_END_EXT:
	    begin
	       gmii_rx_er_m_set = 1;
	         
	       pcs_rx_next = S_PCS_RX_EPD2_CHECK_END;  
	    end
	  
	  S_PCS_RX_DATA_ERROR:
	    begin 
	       gmii_rx_er_m_set = 1;
	       
	       pcs_rx_next = S_PCS_RX_RECEIVE;
	    end
	  
	  S_PCS_RX_DATA:
	    begin
	       gmii_rx_er_m_clr = 1; gmii_rxd_m_set = 1;
	       
	       pcs_rx_next = S_PCS_RX_RECEIVE;
	    end
	endcase

	if      (~signal_detect)  pcs_rx_next = S_PCS_RX_LINK_FAILED;
	else if (~sync_status_d3) pcs_rx_next = S_PCS_RX_LINK_FAILED;    
	else if (soft_reset)      pcs_rx_next = S_PCS_RX_WAIT_K;
	  
     end 
   
endmodule
"""

omsp_frontend = """
`define PMEM_SIZE_4_KB
//`define PMEM_SIZE_2_KB
//`define PMEM_SIZE_1_KB


// Data Memory Size:
//                     Uncomment the required memory size
//-------------------------------------------------------
//`define DMEM_SIZE_CUSTOM
//`define DMEM_SIZE_32_KB
//`define DMEM_SIZE_24_KB
//`define DMEM_SIZE_16_KB
//`define DMEM_SIZE_10_KB
//`define DMEM_SIZE_8_KB
//`define DMEM_SIZE_5_KB
//`define DMEM_SIZE_4_KB
//`define DMEM_SIZE_2p5_KB
//`define DMEM_SIZE_2_KB
`define DMEM_SIZE_1_KB
//`define DMEM_SIZE_512_B
//`define DMEM_SIZE_256_B
//`define DMEM_SIZE_128_B


// Include/Exclude Hardware Multiplier
`define MULTIPLIER


// Include/Exclude Serial Debug interface
`define DBG_EN


//============================================================================
//============================================================================
// ADVANCED SYSTEM CONFIGURATION (FOR EXPERIENCED USERS)
//============================================================================
//============================================================================

//-------------------------------------------------------
// Custom user version number
//-------------------------------------------------------
// This 5 bit field can be freely used in order to allow
// custom identification of the system through the debug
// interface.
// (see CPU_ID.USER_VERSION field in the documentation)
//-------------------------------------------------------
`define USER_VERSION 5'b00000


//-------------------------------------------------------
// Include/Exclude Watchdog timer
//-------------------------------------------------------
// When excluded, the following functionality will be
// lost:
//        - Watchog (both interval and watchdog modes)
//        - NMI interrupt edge selection
//        - Possibility to generate a software PUC reset
//-------------------------------------------------------
`define WATCHDOG


//-------------------------------------------------------
// Include/Exclude DMA interface support
//-------------------------------------------------------
`define DMA_IF_EN


//-------------------------------------------------------
// Include/Exclude Non-Maskable-Interrupt support
//-------------------------------------------------------
`define NMI


//-------------------------------------------------------
// Number of available IRQs
//-------------------------------------------------------
// Indicates the number of interrupt vectors supported
// (16, 32 or 64).
//-------------------------------------------------------
`define IRQ_16
//`define IRQ_32
//`define IRQ_64


//-------------------------------------------------------
// Input synchronizers
//-------------------------------------------------------
// In some cases, the asynchronous input ports might
// already be synchronized externally.
// If an extensive CDC design review showed that this
// is really the case,  the individual synchronizers
// can be disabled with the following defines.
//
// Notes:
//        - all three signals are all sampled in the MCLK domain
//
//        - the dbg_en signal reset the debug interface
//         when 0. Therefore make sure it is glitch free.
//
//-------------------------------------------------------
`define SYNC_NMI
//`define SYNC_CPU_EN
//`define SYNC_DBG_EN


//-------------------------------------------------------
// Peripheral Memory Space:
//-------------------------------------------------------
// The original MSP430 architecture map the peripherals
// from 0x0000 to 0x01FF (i.e. 512B of the memory space).
// The following defines allow you to expand this space
// up to 32 kB (i.e. from 0x0000 to 0x7fff).
// As a consequence, the data memory mapping will be
// shifted up and a custom linker script will therefore
// be required by the GCC compiler.
//-------------------------------------------------------
//`define PER_SIZE_CUSTOM
//`define PER_SIZE_32_KB
//`define PER_SIZE_16_KB
//`define PER_SIZE_8_KB
//`define PER_SIZE_4_KB
//`define PER_SIZE_2_KB
//`define PER_SIZE_1_KB
`define PER_SIZE_512_B


//-------------------------------------------------------
// Defines the debugger CPU_CTL.RST_BRK_EN reset value
// (CPU break on PUC reset)
//-------------------------------------------------------
// When defined, the CPU will automatically break after
// a PUC occurrence by default. This is typically useful
// when the program memory can only be initialized through
// the serial debug interface.
//-------------------------------------------------------
`define DBG_RST_BRK_EN


//============================================================================
//============================================================================
// EXPERT SYSTEM CONFIGURATION ( !!!! EXPERTS ONLY !!!! )
//============================================================================
//============================================================================
//
// IMPORTANT NOTE:  Please update following configuration options ONLY if
//                 you have a good reason to do so... and if you know what
//                 you are doing :-P
//
//============================================================================

//-------------------------------------------------------
// Select serial debug interface protocol
//-------------------------------------------------------
//    DBG_UART -> Enable UART (8N1) debug interface
//    DBG_I2C  -> Enable I2C debug interface
//-------------------------------------------------------
`define DBG_UART
//`define DBG_I2C


//-------------------------------------------------------
// Enable the I2C broadcast address
//-------------------------------------------------------
// For multicore systems, a common I2C broadcast address
// can be given to all oMSP cores in order to
// synchronously RESET, START, STOP, or STEP all CPUs
// at once with a single I2C command.
// If you have a single openMSP430 in your system,
// this option can stay commented-out.
//-------------------------------------------------------
//`define DBG_I2C_BROADCAST


//-------------------------------------------------------
// Number of hardware breakpoint/watchpoint units
// (each unit contains two hardware addresses available
// for breakpoints or watchpoints):
//   - DBG_HWBRK_0 -> Include hardware breakpoints unit 0
//   - DBG_HWBRK_1 -> Include hardware breakpoints unit 1
//   - DBG_HWBRK_2 -> Include hardware breakpoints unit 2
//   - DBG_HWBRK_3 -> Include hardware breakpoints unit 3
//-------------------------------------------------------
// Please keep in mind that hardware breakpoints only
// make sense whenever the program memory is not an SRAM
// (i.e. Flash/OTP/ROM/...) or when you are interested
// in data breakpoints.
//-------------------------------------------------------
//`define  DBG_HWBRK_0
//`define  DBG_HWBRK_1
//`define  DBG_HWBRK_2
//`define  DBG_HWBRK_3


//-------------------------------------------------------
// Enable/Disable the hardware breakpoint RANGE mode
//-------------------------------------------------------
// When enabled this feature allows the hardware breakpoint
// units to stop the cpu whenever an instruction or data
// access lays within an address range.
// Note that this feature is not supported by GDB.
//-------------------------------------------------------
//`define DBG_HWBRK_RANGE


//-------------------------------------------------------
// Custom Program/Data and Peripheral Memory Spaces
//-------------------------------------------------------
// The following values are valid only if the
// corresponding *_SIZE_CUSTOM defines are uncommented:
//
//  - *_SIZE   : size of the section in bytes.
//  - *_AWIDTH : address port width, this value must allow
//               to address all WORDS of the section
//               (i.e. the *_SIZE divided by 2)
//-------------------------------------------------------

// Custom Program memory    (enabled with PMEM_SIZE_CUSTOM)
`define PMEM_CUSTOM_AWIDTH      10
`define PMEM_CUSTOM_SIZE      2048

// Custom Data memory       (enabled with DMEM_SIZE_CUSTOM)
`define DMEM_CUSTOM_AWIDTH       6
`define DMEM_CUSTOM_SIZE       128

// Custom Peripheral memory (enabled with PER_SIZE_CUSTOM)
`define PER_CUSTOM_AWIDTH        8
`define PER_CUSTOM_SIZE        512


//-------------------------------------------------------
// ASIC version
//-------------------------------------------------------
// When uncommented, this define will enable the
// ASIC system configuration section (see below) and
// will activate scan support for production test.
//
// WARNING: if you target an FPGA, leave this define
//          commented.
//-------------------------------------------------------
`define ASIC


//============================================================================
//============================================================================
// ASIC SYSTEM CONFIGURATION ( !!!! EXPERTS/PROFESSIONALS ONLY !!!! )
//============================================================================
//============================================================================
`ifdef ASIC

//===============================================================
// FINE GRAINED CLOCK GATING
//===============================================================

//-------------------------------------------------------
// When uncommented, this define will enable the fine
// grained clock gating of all registers in the core.
//-------------------------------------------------------
`define CLOCK_GATING


//===============================================================
// ASIC CLOCKING
//===============================================================

//-------------------------------------------------------
// When uncommented, this define will enable the ASIC
// architectural clock gating as well as the advanced low
// power modes support (most common).
// Comment this out in order to get FPGA-like clocking.
//-------------------------------------------------------
`define ASIC_CLOCKING


`ifdef ASIC_CLOCKING
//===============================================================
// LFXT CLOCK DOMAIN
//===============================================================

//-------------------------------------------------------
// When uncommented, this define will enable the lfxt_clk
// clock domain.
// When commented out, the whole chip is clocked with dco_clk.
//-------------------------------------------------------
`define LFXT_DOMAIN


//===============================================================
// CLOCK MUXES
//===============================================================

//-------------------------------------------------------
// MCLK: Clock Mux
//-------------------------------------------------------
// When uncommented, this define will enable the
// MCLK clock MUX allowing the selection between
// DCO_CLK and LFXT_CLK with the BCSCTL2.SELMx register.
// When commented, DCO_CLK is selected.
//-------------------------------------------------------
//`define MCLK_MUX

//-------------------------------------------------------
// SMCLK: Clock Mux
//-------------------------------------------------------
// When uncommented, this define will enable the
// SMCLK clock MUX allowing the selection between
// DCO_CLK and LFXT_CLK with the BCSCTL2.SELS register.
// When commented, DCO_CLK is selected.
//-------------------------------------------------------
//`define SMCLK_MUX

//-------------------------------------------------------
// WATCHDOG: Clock Mux
//-------------------------------------------------------
// When uncommented, this define will enable the
// Watchdog clock MUX allowing the selection between
// ACLK and SMCLK with the WDTCTL.WDTSSEL register.
// When commented out, ACLK is selected if the
// WATCHDOG_NOMUX_ACLK define is uncommented, SMCLK is
// selected otherwise.
//-------------------------------------------------------
//`define WATCHDOG_MUX
//`define WATCHDOG_NOMUX_ACLK


//===============================================================
// CLOCK DIVIDERS
//===============================================================

//-------------------------------------------------------
// MCLK: Clock divider
//-------------------------------------------------------
// When uncommented, this define will enable the
// MCLK clock divider (/1/2/4/8)
//-------------------------------------------------------
`define MCLK_DIVIDER

//-------------------------------------------------------
// SMCLK: Clock divider (/1/2/4/8)
//-------------------------------------------------------
// When uncommented, this define will enable the
// SMCLK clock divider
//-------------------------------------------------------
`define SMCLK_DIVIDER

//-------------------------------------------------------
// ACLK: Clock divider (/1/2/4/8)
//-------------------------------------------------------
// When uncommented, this define will enable the
// ACLK clock divider
//-------------------------------------------------------
`define ACLK_DIVIDER


//===============================================================
// LOW POWER MODES
//===============================================================

//-------------------------------------------------------
// LOW POWER MODE: CPUOFF
//-------------------------------------------------------
// When uncommented, this define will include the
// clock gate allowing to switch off MCLK in
// all low power modes: LPM0, LPM1, LPM2, LPM3, LPM4
//-------------------------------------------------------
`define CPUOFF_EN

//-------------------------------------------------------
// LOW POWER MODE: SCG0
//-------------------------------------------------------
// When uncommented, this define will enable the
// DCO_ENABLE/WKUP port control (always 1 when commented).
// This allows to switch off the DCO oscillator in the
// following low power modes: LPM1, LPM3, LPM4
//-------------------------------------------------------
`define SCG0_EN

//-------------------------------------------------------
// LOW POWER MODE: SCG1
//-------------------------------------------------------
// When uncommented, this define will include the
// clock gate allowing to switch off SMCLK in
// the following low power modes: LPM2, LPM3, LPM4
//-------------------------------------------------------
`define SCG1_EN

//-------------------------------------------------------
// LOW POWER MODE: OSCOFF
//-------------------------------------------------------
// When uncommented, this define will include the
// LFXT_CLK clock gate and enable the LFXT_ENABLE/WKUP
// port control (always 1 when commented).
// This allows to switch off the low frequency oscillator
// in the following low power modes: LPM4
//-------------------------------------------------------
`define OSCOFF_EN

//-------------------------------------------------------
// SCAN REPAIR NEG-EDGE CLOCKED FLIP-FLOPS
//-------------------------------------------------------
// When uncommented, a scan mux will be infered to
// replace all inverted clocks with regular ones when
// in scan mode.
//
// Note: standard scan insertion tool can usually deal
//       with mixed rising/falling edge FF... so there
//       is usually no need to uncomment this.
//-------------------------------------------------------
//`define SCAN_REPAIR_INV_CLOCKS

`endif
`endif

//==========================================================================//
//==========================================================================//
//==========================================================================//
//==========================================================================//
//=====        SYSTEM CONSTANTS --- !!!!!!!! DO NOT EDIT !!!!!!!!      =====//
//==========================================================================//
//==========================================================================//
//==========================================================================//
//==========================================================================//

//
// PROGRAM, DATA & PERIPHERAL MEMORY CONFIGURATION
//==================================================

// Program Memory Size
`ifdef PMEM_SIZE_59_KB
  `define PMEM_AWIDTH      15
  `define PMEM_SIZE     60416
`endif
`ifdef PMEM_SIZE_55_KB
  `define PMEM_AWIDTH      15
  `define PMEM_SIZE     56320
`endif
`ifdef PMEM_SIZE_54_KB
  `define PMEM_AWIDTH      15
  `define PMEM_SIZE     55296
`endif
`ifdef PMEM_SIZE_51_KB
  `define PMEM_AWIDTH      15
  `define PMEM_SIZE     52224
`endif
`ifdef PMEM_SIZE_48_KB
  `define PMEM_AWIDTH      15
  `define PMEM_SIZE     49152
`endif
`ifdef PMEM_SIZE_41_KB
  `define PMEM_AWIDTH      15
  `define PMEM_SIZE     41984
`endif
`ifdef PMEM_SIZE_32_KB
  `define PMEM_AWIDTH      14
  `define PMEM_SIZE     32768
`endif
`ifdef PMEM_SIZE_24_KB
  `define PMEM_AWIDTH      14
  `define PMEM_SIZE     24576
`endif
`ifdef PMEM_SIZE_16_KB
  `define PMEM_AWIDTH      13
  `define PMEM_SIZE     16384
`endif
`ifdef PMEM_SIZE_12_KB
  `define PMEM_AWIDTH      13
  `define PMEM_SIZE     12288
`endif
`ifdef PMEM_SIZE_8_KB
  `define PMEM_AWIDTH      12
  `define PMEM_SIZE      8192
`endif
`ifdef PMEM_SIZE_4_KB
  `define PMEM_AWIDTH      11
  `define PMEM_SIZE      4096
`endif
`ifdef PMEM_SIZE_2_KB
  `define PMEM_AWIDTH      10
  `define PMEM_SIZE      2048
`endif
`ifdef PMEM_SIZE_1_KB
  `define PMEM_AWIDTH       9
  `define PMEM_SIZE      1024
`endif
`ifdef PMEM_SIZE_CUSTOM
  `define PMEM_AWIDTH       `PMEM_CUSTOM_AWIDTH
  `define PMEM_SIZE         `PMEM_CUSTOM_SIZE
`endif

// Data Memory Size
`ifdef DMEM_SIZE_32_KB
  `define DMEM_AWIDTH       14
  `define DMEM_SIZE      32768
`endif
`ifdef DMEM_SIZE_24_KB
  `define DMEM_AWIDTH       14
  `define DMEM_SIZE      24576
`endif
`ifdef DMEM_SIZE_16_KB
  `define DMEM_AWIDTH       13
  `define DMEM_SIZE      16384
`endif
`ifdef DMEM_SIZE_10_KB
  `define DMEM_AWIDTH       13
  `define DMEM_SIZE      10240
`endif
`ifdef DMEM_SIZE_8_KB
  `define DMEM_AWIDTH       12
  `define DMEM_SIZE       8192
`endif
`ifdef DMEM_SIZE_5_KB
  `define DMEM_AWIDTH       12
  `define DMEM_SIZE       5120
`endif
`ifdef DMEM_SIZE_4_KB
  `define DMEM_AWIDTH       11
  `define DMEM_SIZE       4096
`endif
`ifdef DMEM_SIZE_2p5_KB
  `define DMEM_AWIDTH       11
  `define DMEM_SIZE       2560
`endif
`ifdef DMEM_SIZE_2_KB
  `define DMEM_AWIDTH       10
  `define DMEM_SIZE       2048
`endif
`ifdef DMEM_SIZE_1_KB
  `define DMEM_AWIDTH        9
  `define DMEM_SIZE       1024
`endif
`ifdef DMEM_SIZE_512_B
  `define DMEM_AWIDTH        8
  `define DMEM_SIZE        512
`endif
`ifdef DMEM_SIZE_256_B
  `define DMEM_AWIDTH        7
  `define DMEM_SIZE        256
`endif
`ifdef DMEM_SIZE_128_B
  `define DMEM_AWIDTH        6
  `define DMEM_SIZE        128
`endif
`ifdef DMEM_SIZE_CUSTOM
  `define DMEM_AWIDTH       `DMEM_CUSTOM_AWIDTH
  `define DMEM_SIZE         `DMEM_CUSTOM_SIZE
`endif

// Peripheral Memory Size
`ifdef PER_SIZE_32_KB
  `define PER_AWIDTH        14
  `define PER_SIZE       32768
`endif
`ifdef PER_SIZE_16_KB
  `define PER_AWIDTH        13
  `define PER_SIZE       16384
`endif
`ifdef PER_SIZE_8_KB
  `define PER_AWIDTH        12
  `define PER_SIZE        8192
`endif
`ifdef PER_SIZE_4_KB
  `define PER_AWIDTH        11
  `define PER_SIZE        4096
`endif
`ifdef PER_SIZE_2_KB
  `define PER_AWIDTH        10
  `define PER_SIZE        2048
`endif
`ifdef PER_SIZE_1_KB
  `define PER_AWIDTH         9
  `define PER_SIZE        1024
`endif
`ifdef PER_SIZE_512_B
  `define PER_AWIDTH         8
  `define PER_SIZE         512
`endif
`ifdef PER_SIZE_CUSTOM
  `define PER_AWIDTH        `PER_CUSTOM_AWIDTH
  `define PER_SIZE          `PER_CUSTOM_SIZE
`endif

// Data Memory Base Adresses
`define DMEM_BASE  `PER_SIZE

// Program & Data Memory most significant address bit (for 16 bit words)
`define PMEM_MSB   `PMEM_AWIDTH-1
`define DMEM_MSB   `DMEM_AWIDTH-1
`define PER_MSB    `PER_AWIDTH-1

// Number of available IRQs
`ifdef  IRQ_16
`define IRQ_NR 16
`endif
`ifdef  IRQ_32
`define IRQ_NR 32
`define IRQ_NR_GE_32
`endif
`ifdef  IRQ_64
`define IRQ_NR 64
`define IRQ_NR_GE_32
`endif

//
// STATES, REGISTER FIELDS, ...
//======================================

// Instructions type
`define INST_SO  0
`define INST_JMP 1
`define INST_TO  2

// Single-operand arithmetic
`define RRC    0
`define SWPB   1
`define RRA    2
`define SXT    3
`define PUSH   4
`define CALL   5
`define RETI   6
`define IRQ    7

// Conditional jump
`define JNE    0
`define JEQ    1
`define JNC    2
`define JC     3
`define JN     4
`define JGE    5
`define JL     6
`define JMP    7

// Two-operand arithmetic
`define MOV    0
`define ADD    1
`define ADDC   2
`define SUBC   3
`define SUB    4
`define CMP    5
`define DADD   6
`define BIT    7
`define BIC    8
`define BIS    9
`define XOR   10
`define AND   11

// Addressing modes
`define DIR      0
`define IDX      1
`define INDIR    2
`define INDIR_I  3
`define SYMB     4
`define IMM      5
`define ABS      6
`define CONST    7

// Instruction state machine
`define I_IRQ_FETCH 3'h0
`define I_IRQ_DONE  3'h1
`define I_DEC       3'h2
`define I_EXT1      3'h3
`define I_EXT2      3'h4
`define I_IDLE      3'h5

// Execution state machine
// (swapped E_IRQ_0 and E_IRQ_2 values to suppress glitch generation warning from lint tool)
`define E_IRQ_0     4'h2
`define E_IRQ_1     4'h1
`define E_IRQ_2     4'h0
`define E_IRQ_3     4'h3
`define E_IRQ_4     4'h4
`define E_SRC_AD    4'h5
`define E_SRC_RD    4'h6
`define E_SRC_WR    4'h7
`define E_DST_AD    4'h8
`define E_DST_RD    4'h9
`define E_DST_WR    4'hA
`define E_EXEC      4'hB
`define E_JUMP      4'hC
`define E_IDLE      4'hD

// ALU control signals
`define ALU_SRC_INV   0
`define ALU_INC       1
`define ALU_INC_C     2
`define ALU_ADD       3
`define ALU_AND       4
`define ALU_OR        5
`define ALU_XOR       6
`define ALU_DADD      7
`define ALU_STAT_7    8
`define ALU_STAT_F    9
`define ALU_SHIFT    10
`define EXEC_NO_WR   11

// Debug interface
`define DBG_UART_WR   18
`define DBG_UART_BW   17
`define DBG_UART_ADDR 16:11

// Debug interface CPU_CTL register
`define HALT        0
`define RUN         1
`define ISTEP       2
`define SW_BRK_EN   3
`define FRZ_BRK_EN  4
`define RST_BRK_EN  5
`define CPU_RST     6

// Debug interface CPU_STAT register
`define HALT_RUN    0
`define PUC_PND     1
`define SWBRK_PND   3
`define HWBRK0_PND  4
`define HWBRK1_PND  5

// Debug interface BRKx_CTL register
`define BRK_MODE_RD 0
`define BRK_MODE_WR 1
`define BRK_MODE    1:0
`define BRK_EN      2
`define BRK_I_EN    3
`define BRK_RANGE   4

// Basic clock module: BCSCTL1 Control Register
`define DIVAx       5:4
`define DMA_CPUOFF  0
`define DMA_OSCOFF  1
`define DMA_SCG0    2
`define DMA_SCG1    3

// Basic clock module: BCSCTL2 Control Register
`define SELMx       7
`define DIVMx       5:4
`define SELS        3
`define DIVSx       2:1

// MCLK Clock gate
`ifdef CPUOFF_EN
  `define MCLK_CGATE
`else
`ifdef MCLK_DIVIDER
  `define MCLK_CGATE
`endif
`endif

// SMCLK Clock gate
`ifdef SCG1_EN
  `define SMCLK_CGATE
`else
`ifdef SMCLK_DIVIDER
  `define SMCLK_CGATE
`endif
`endif

//
// DEBUG INTERFACE EXTRA CONFIGURATION
//======================================

// Debug interface: CPU version
//   1 - FPGA support only (Pre-BSD licence era)
//   2 - Add ASIC support
//   3 - Add DMA interface support
`define CPU_VERSION   3'h3

// Debug interface: Software breakpoint opcode
`define DBG_SWBRK_OP 16'h4343

// Debug UART interface auto data synchronization
// If the following define is commented out, then
// the DBG_UART_BAUD and DBG_DCO_FREQ need to be properly
// defined.
`define DBG_UART_AUTO_SYNC

// Debug UART interface data rate
//      In order to properly setup the UART debug interface, you
//      need to specify the DCO_CLK frequency (DBG_DCO_FREQ) and
//      the chosen BAUD rate from the UART interface.
//
//`define DBG_UART_BAUD    9600
//`define DBG_UART_BAUD   19200
//`define DBG_UART_BAUD   38400
//`define DBG_UART_BAUD   57600
//`define DBG_UART_BAUD  115200
//`define DBG_UART_BAUD  230400
//`define DBG_UART_BAUD  460800
//`define DBG_UART_BAUD  576000
//`define DBG_UART_BAUD  921600
`define DBG_UART_BAUD 2000000
`define DBG_DCO_FREQ  20000000
`define DBG_UART_CNT ((`DBG_DCO_FREQ/`DBG_UART_BAUD)-1)

// Debug interface input synchronizer
`define SYNC_DBG_UART_RXD

// Enable/Disable the hardware breakpoint RANGE mode
`ifdef DBG_HWBRK_RANGE
 `define HWBRK_RANGE 1'b1
`else
 `define HWBRK_RANGE 1'b0
`endif

// Counter width for the debug interface UART
`define DBG_UART_XFER_CNT_W 16

// Check configuration
`ifdef DBG_EN
 `ifdef DBG_UART
   `ifdef DBG_I2C
CONFIGURATION ERROR: I2C AND UART DEBUG INTERFACE ARE BOTH ENABLED
   `endif
 `else
   `ifdef DBG_I2C
   `else
CONFIGURATION ERROR: I2C OR UART DEBUG INTERFACE SHOULD BE ENABLED
   `endif
 `endif
`endif

//
// MULTIPLIER CONFIGURATION
//======================================

// If uncommented, the following define selects
// the 16x16 multiplier (1 cycle) instead of the
// default 16x8 multplier (2 cycles)
//`define MPY_16x16

//======================================
// CONFIGURATION CHECKS
//======================================

`ifdef  IRQ_16
  `ifdef  IRQ_32
CONFIGURATION ERROR: ONLY ONE OF THE IRQ NUMBER OPTION CAN BE SELECTED
  `endif
  `ifdef  IRQ_64
CONFIGURATION ERROR: ONLY ONE OF THE IRQ NUMBER OPTION CAN BE SELECTED
  `endif
`endif
`ifdef  IRQ_32
  `ifdef  IRQ_64
CONFIGURATION ERROR: ONLY ONE OF THE IRQ NUMBER OPTION CAN BE SELECTED
  `endif
`endif
`ifdef LFXT_DOMAIN
`else
 `ifdef MCLK_MUX
CONFIGURATION ERROR: THE MCLK_MUX CAN ONLY BE ENABLED IF THE LFXT_DOMAIN IS ENABLED AS WELL
 `endif
 `ifdef SMCLK_MUX
CONFIGURATION ERROR: THE SMCLK_MUX CAN ONLY BE ENABLED IF THE LFXT_DOMAIN IS ENABLED AS WELL
 `endif
 `ifdef WATCHDOG_MUX
CONFIGURATION ERROR: THE WATCHDOG_MUX CAN ONLY BE ENABLED IF THE LFXT_DOMAIN IS ENABLED AS WELL
 `else
   `ifdef WATCHDOG_NOMUX_ACLK
CONFIGURATION ERROR: THE WATCHDOG_NOMUX_ACLK CAN ONLY BE ENABLED IF THE LFXT_DOMAIN IS ENABLED AS WELL
   `endif
 `endif
 `ifdef OSCOFF_EN
CONFIGURATION ERROR: THE OSCOFF LOW POWER MODE CAN ONLY BE ENABLED IF THE LFXT_DOMAIN IS ENABLED AS WELL
 `endif
`endif


module  omsp_frontend (

// OUTPUTs
    cpu_halt_st,                       // Halt/Run status from CPU
    decode_noirq,                      // Frontend decode instruction
    e_state,                           // Execution state
    exec_done,                         // Execution completed
    inst_ad,                           // Decoded Inst: destination addressing mode
    inst_as,                           // Decoded Inst: source addressing mode
    inst_alu,                          // ALU control signals
    inst_bw,                           // Decoded Inst: byte width
    inst_dest,                         // Decoded Inst: destination (one hot)
    inst_dext,                         // Decoded Inst: destination extended instruction word
    inst_irq_rst,                      // Decoded Inst: Reset interrupt
    inst_jmp,                          // Decoded Inst: Conditional jump
    inst_mov,                          // Decoded Inst: mov instruction
    inst_sext,                         // Decoded Inst: source extended instruction word
    inst_so,                           // Decoded Inst: Single-operand arithmetic
    inst_src,                          // Decoded Inst: source (one hot)
    inst_type,                         // Decoded Instruction type
    irq_acc,                           // Interrupt request accepted (one-hot signal)
    mab,                               // Frontend Memory address bus
    mb_en,                             // Frontend Memory bus enable
    mclk_dma_enable,                   // DMA Sub-System Clock enable
    mclk_dma_wkup,                     // DMA Sub-System Clock wake-up (asynchronous)
    mclk_enable,                       // Main System Clock enable
    mclk_wkup,                         // Main System Clock wake-up (asynchronous)
    nmi_acc,                           // Non-Maskable interrupt request accepted
    pc,                                // Program counter
    pc_nxt,                            // Next PC value (for CALL & IRQ)

// INPUTs
    cpu_en_s,                          // Enable CPU code execution (synchronous)
    cpu_halt_cmd,                      // Halt CPU command
    cpuoff,                            // Turns off the CPU
    dbg_reg_sel,                       // Debug selected register for rd/wr access
    dma_en,                            // Direct Memory Access enable (high active)
    dma_wkup,                          // DMA Sub-System Wake-up (asynchronous and non-glitchy)
    fe_pmem_wait,                      // Frontend wait for Instruction fetch
    gie,                               // General interrupt enable
    irq,                               // Maskable interrupts
    mclk,                              // Main system clock
    mdb_in,                            // Frontend Memory data bus input
    nmi_pnd,                           // Non-maskable interrupt pending
    nmi_wkup,                          // NMI Wakeup
    pc_sw,                             // Program counter software value
    pc_sw_wr,                          // Program counter software write
    puc_rst,                           // Main system reset
    scan_enable,                       // Scan enable (active during scan shifting)
    wdt_irq,                           // Watchdog-timer interrupt
    wdt_wkup,                          // Watchdog Wakeup
    wkup                               // System Wake-up (asynchronous)
);

// OUTPUTs
//=========
output               cpu_halt_st;      // Halt/Run status from CPU
output               decode_noirq;     // Frontend decode instruction
output         [3:0] e_state;          // Execution state
output               exec_done;        // Execution completed
output         [7:0] inst_ad;          // Decoded Inst: destination addressing mode
output         [7:0] inst_as;          // Decoded Inst: source addressing mode
output        [11:0] inst_alu;         // ALU control signals
output               inst_bw;          // Decoded Inst: byte width
output        [15:0] inst_dest;        // Decoded Inst: destination (one hot)
output        [15:0] inst_dext;        // Decoded Inst: destination extended instruction word
output               inst_irq_rst;     // Decoded Inst: Reset interrupt
output         [7:0] inst_jmp;         // Decoded Inst: Conditional jump
output               inst_mov;         // Decoded Inst: mov instruction
output        [15:0] inst_sext;        // Decoded Inst: source extended instruction word
output         [7:0] inst_so;          // Decoded Inst: Single-operand arithmetic
output        [15:0] inst_src;         // Decoded Inst: source (one hot)
output         [2:0] inst_type;        // Decoded Instruction type
output [`IRQ_NR-3:0] irq_acc;          // Interrupt request accepted (one-hot signal)
output        [15:0] mab;              // Frontend Memory address bus
output               mb_en;            // Frontend Memory bus enable
output               mclk_dma_enable;  // DMA Sub-System Clock enable
output               mclk_dma_wkup;    // DMA Sub-System Clock wake-up (asynchronous)
output               mclk_enable;      // Main System Clock enable
output               mclk_wkup;        // Main System Clock wake-up (asynchronous)
output               nmi_acc;          // Non-Maskable interrupt request accepted
output        [15:0] pc;               // Program counter
output        [15:0] pc_nxt;           // Next PC value (for CALL & IRQ)

// INPUTs
//=========
input                cpu_en_s;         // Enable CPU code execution (synchronous)
input                cpu_halt_cmd;     // Halt CPU command
input                cpuoff;           // Turns off the CPU
input          [3:0] dbg_reg_sel;      // Debug selected register for rd/wr access
input                dma_en;           // Direct Memory Access enable (high active)
input                dma_wkup;         // DMA Sub-System Wake-up (asynchronous and non-glitchy)
input                fe_pmem_wait;     // Frontend wait for Instruction fetch
input                gie;              // General interrupt enable
input  [`IRQ_NR-3:0] irq;              // Maskable interrupts
input                mclk;             // Main system clock
input         [15:0] mdb_in;           // Frontend Memory data bus input
input                nmi_pnd;          // Non-maskable interrupt pending
input                nmi_wkup;         // NMI Wakeup
input         [15:0] pc_sw;            // Program counter software value
input                pc_sw_wr;         // Program counter software write
input                puc_rst;          // Main system reset
input                scan_enable;      // Scan enable (active during scan shifting)
input                wdt_irq;          // Watchdog-timer interrupt
input                wdt_wkup;         // Watchdog Wakeup
input                wkup;             // System Wake-up (asynchronous)


//=============================================================================
// 1)  UTILITY FUNCTIONS
//=============================================================================

// 64 bits one-hot decoder
function [63:0] one_hot64;
   input  [5:0] binary;
   begin
      one_hot64         = 64'h0000_0000_0000_0000;
      one_hot64[binary] =  1'b1;
   end
endfunction

// 16 bits one-hot decoder
function [15:0] one_hot16;
   input  [3:0] binary;
   begin
      one_hot16         = 16'h0000;
      one_hot16[binary] =  1'b1;
   end
endfunction

// 8 bits one-hot decoder
function [7:0] one_hot8;
   input  [2:0] binary;
   begin
      one_hot8         = 8'h00;
      one_hot8[binary] = 1'b1;
   end
endfunction

// Get IRQ number
function  [5:0] get_irq_num;
   input [62:0] irq_all;
   integer      ii;
   begin
      get_irq_num = 6'h3f;
      for (ii = 62; ii >= 0; ii = ii - 1)
        if (&get_irq_num & irq_all[ii]) get_irq_num = ii[5:0];
   end
endfunction


//=============================================================================
// 2)  PARAMETER DEFINITIONS
//=============================================================================

//
// 2.1) Instruction State machine definitons
//-------------------------------------------

parameter I_IRQ_FETCH = `I_IRQ_FETCH;
parameter I_IRQ_DONE  = `I_IRQ_DONE;
parameter I_DEC       = `I_DEC;        // New instruction ready for decode
parameter I_EXT1      = `I_EXT1;       // 1st Extension word
parameter I_EXT2      = `I_EXT2;       // 2nd Extension word
parameter I_IDLE      = `I_IDLE;       // CPU is in IDLE mode

//
// 2.2) Execution State machine definitons
//-------------------------------------------

parameter E_IRQ_0     = `E_IRQ_0;
parameter E_IRQ_1     = `E_IRQ_1;
parameter E_IRQ_2     = `E_IRQ_2;
parameter E_IRQ_3     = `E_IRQ_3;
parameter E_IRQ_4     = `E_IRQ_4;
parameter E_SRC_AD    = `E_SRC_AD;
parameter E_SRC_RD    = `E_SRC_RD;
parameter E_SRC_WR    = `E_SRC_WR;
parameter E_DST_AD    = `E_DST_AD;
parameter E_DST_RD    = `E_DST_RD;
parameter E_DST_WR    = `E_DST_WR;
parameter E_EXEC      = `E_EXEC;
parameter E_JUMP      = `E_JUMP;
parameter E_IDLE      = `E_IDLE;


//=============================================================================
// 3)  FRONTEND STATE MACHINE
//=============================================================================

// The wire "conv" is used as state bits to calculate the next response
reg  [2:0] i_state;
reg  [2:0] i_state_nxt;

reg  [1:0] inst_sz;
wire [1:0] inst_sz_nxt;
wire       irq_detect;
wire [2:0] inst_type_nxt;
wire       is_const;
reg [15:0] sconst_nxt;
reg  [3:0] e_state_nxt;

// CPU on/off through an external interface (debug or mstr) or cpu_en port
wire   cpu_halt_req = cpu_halt_cmd | ~cpu_en_s;

// States Transitions
always @(i_state    or inst_sz  or inst_sz_nxt  or pc_sw_wr or exec_done or
         irq_detect or cpuoff   or cpu_halt_req or e_state)
    case(i_state)
      I_IDLE     : i_state_nxt = (irq_detect & ~cpu_halt_req) ? I_IRQ_FETCH :
                                 (~cpuoff    & ~cpu_halt_req) ? I_DEC       : I_IDLE;
      I_IRQ_FETCH: i_state_nxt =  I_IRQ_DONE;
      I_IRQ_DONE : i_state_nxt =  I_DEC;
      I_DEC      : i_state_nxt =  irq_detect                  ? I_IRQ_FETCH :
                          (cpuoff | cpu_halt_req) & exec_done ? I_IDLE      :
                            cpu_halt_req & (e_state==E_IDLE)  ? I_IDLE      :
                                  pc_sw_wr                    ? I_DEC       :
                             ~exec_done & ~(e_state==E_IDLE)  ? I_DEC       :        // Wait in decode state
                                  (inst_sz_nxt!=2'b00)        ? I_EXT1      : I_DEC; // until execution is completed
      I_EXT1     : i_state_nxt =  pc_sw_wr                    ? I_DEC       :
                                  (inst_sz!=2'b01)            ? I_EXT2      : I_DEC;
      I_EXT2     : i_state_nxt =  I_DEC;
    // pragma coverage off
      default    : i_state_nxt =  I_IRQ_FETCH;
    // pragma coverage on
    endcase

// State machine
always @(posedge mclk or posedge puc_rst)
  if (puc_rst) i_state  <= I_IRQ_FETCH;
  else         i_state  <= i_state_nxt;

// Utility signals
wire   decode_noirq =  ((i_state==I_DEC) &  (exec_done | (e_state==E_IDLE)));
wire   decode       =  decode_noirq | irq_detect;
wire   fetch        = ~((i_state==I_DEC) & ~(exec_done | (e_state==E_IDLE))) & ~(e_state_nxt==E_IDLE);

// Halt/Run CPU status
reg    cpu_halt_st;
always @(posedge mclk or posedge puc_rst)
  if (puc_rst)  cpu_halt_st <= 1'b0;
  else          cpu_halt_st <= cpu_halt_req & (i_state_nxt==I_IDLE);


//=============================================================================
// 4)  INTERRUPT HANDLING & SYSTEM WAKEUP
//=============================================================================

//
// 4.1) INTERRUPT HANDLING
//-----------------------------------------

// Detect reset interrupt
reg         inst_irq_rst;
always @(posedge mclk or posedge puc_rst)
  if (puc_rst)                  inst_irq_rst <= 1'b1;
  else if (exec_done)           inst_irq_rst <= 1'b0;

//  Detect other interrupts
assign  irq_detect = (nmi_pnd | ((|irq | wdt_irq) & gie)) & ~cpu_halt_req & ~cpu_halt_st & (exec_done | (i_state==I_IDLE));

`ifdef CLOCK_GATING
wire       mclk_irq_num;
omsp_clock_gate clock_gate_irq_num (.gclk(mclk_irq_num),
                                    .clk (mclk), .enable(irq_detect), .scan_enable(scan_enable));
`else
wire       UNUSED_scan_enable = scan_enable;
wire       mclk_irq_num       = mclk;
`endif

// Combine all IRQs
`ifdef  IRQ_16
wire [62:0] irq_all     = {nmi_pnd, irq, 48'h0000_0000_0000} |
`else
`ifdef  IRQ_32
wire [62:0] irq_all     = {nmi_pnd, irq, 32'h0000_0000}      |
`else
`ifdef  IRQ_64
wire [62:0] irq_all     = {nmi_pnd, irq}                     |
`endif
`endif
`endif
                          {1'b0,    3'h0, wdt_irq, {58{1'b0}}};

// Select highest priority IRQ
reg  [5:0] irq_num;
always @(posedge mclk_irq_num or posedge puc_rst)
  if (puc_rst)         irq_num <= 6'h3f;
`ifdef CLOCK_GATING
  else
`else
  else if (irq_detect)
`endif
                       irq_num <= get_irq_num(irq_all);

// Generate selected IRQ vector address
wire [15:0] irq_addr    = {9'h1ff, irq_num, 1'b0};

// Interrupt request accepted
wire        [63:0] irq_acc_all = one_hot64(irq_num) & {64{(i_state==I_IRQ_FETCH)}};
wire [`IRQ_NR-3:0] irq_acc     = irq_acc_all[61:64-`IRQ_NR];
wire               nmi_acc     = irq_acc_all[62];

//
// 4.2) SYSTEM WAKEUP
//-----------------------------------------
`ifdef CPUOFF_EN

// Generate the main system clock enable signal
                                                    // Keep the clock running if:
wire mclk_enable = inst_irq_rst ? cpu_en_s :        //      - the RESET interrupt is currently executing
                                                    //        and if the CPU is enabled
                                                    // otherwise if:
                  ~((cpuoff | ~cpu_en_s) &          //      - the CPUOFF flag, cpu_en command, instruction
                   (i_state==I_IDLE) &              //        and execution state machines are all two
                   (e_state==E_IDLE));              //        not idle.


// Wakeup condition from maskable interrupts
wire mirq_wkup;
omsp_and_gate and_mirq_wkup     (.y(mirq_wkup),     .a(wkup | wdt_wkup),      .b(gie));

// Combined asynchronous wakeup detection from nmi & irq (masked if the cpu is disabled)
omsp_and_gate and_mclk_wkup     (.y(mclk_wkup),     .a(nmi_wkup | mirq_wkup), .b(cpu_en_s));

// Wakeup condition from DMA interface
  `ifdef DMA_IF_EN
wire mclk_dma_enable = dma_en & cpu_en_s;
omsp_and_gate and_mclk_dma_wkup (.y(mclk_dma_wkup), .a(dma_wkup),             .b(cpu_en_s));
  `else
assign  mclk_dma_wkup   = 1'b0;
assign  mclk_dma_enable = 1'b0;
wire    UNUSED_dma_en   = dma_en;
wire    UNUSED_dma_wkup = dma_wkup;
  `endif
`else

// In the CPUOFF feature is disabled, the wake-up and enable signals are always 1
assign  mclk_dma_wkup   = 1'b1;
assign  mclk_dma_enable = 1'b1;
assign  mclk_wkup       = 1'b1;
assign  mclk_enable     = 1'b1;
wire    UNUSED_dma_en   = dma_en;
wire    UNUSED_wkup     = wkup;
wire    UNUSED_wdt_wkup = wdt_wkup;
wire    UNUSED_nmi_wkup = nmi_wkup;
wire    UNUSED_dma_wkup = dma_wkup;
`endif

//=============================================================================
// 5)  FETCH INSTRUCTION
//=============================================================================

//
// 5.1) PROGRAM COUNTER & MEMORY INTERFACE
//-----------------------------------------

// Program counter
reg  [15:0] pc;

// Compute next PC value
wire [15:0] pc_incr = pc + {14'h0000, fetch, 1'b0};
wire [15:0] pc_nxt  = pc_sw_wr               ? pc_sw    :
                      (i_state==I_IRQ_FETCH) ? irq_addr :
                      (i_state==I_IRQ_DONE)  ? mdb_in   :  pc_incr;

`ifdef CLOCK_GATING
wire       pc_en  = fetch                  |
                    pc_sw_wr               |
                    (i_state==I_IRQ_FETCH) |
                    (i_state==I_IRQ_DONE);
wire       mclk_pc;
omsp_clock_gate clock_gate_pc (.gclk(mclk_pc),
                               .clk (mclk), .enable(pc_en), .scan_enable(scan_enable));
`else
wire       mclk_pc = mclk;
`endif

always @(posedge mclk_pc or posedge puc_rst)
  if (puc_rst)  pc <= 16'h0000;
  else          pc <= pc_nxt;

// Check if Program-Memory has been busy in order to retry Program-Memory access
reg pmem_busy;
always @(posedge mclk or posedge puc_rst)
  if (puc_rst)  pmem_busy <= 1'b0;
  else          pmem_busy <= fe_pmem_wait;

// Memory interface
wire [15:0] mab      = pc_nxt;
wire        mb_en    = fetch | pc_sw_wr | (i_state==I_IRQ_FETCH) | pmem_busy | (cpu_halt_st & ~cpu_halt_req);


//
// 5.2) INSTRUCTION REGISTER
//--------------------------------

// Instruction register
wire [15:0] ir  = mdb_in;

// Detect if source extension word is required
wire is_sext = (inst_as[`IDX] | inst_as[`SYMB] | inst_as[`ABS] | inst_as[`IMM]);

// For the Symbolic addressing mode, add -2 to the extension word in order
// to make up for the PC address
wire [15:0] ext_incr = ((i_state==I_EXT1)     &  inst_as[`SYMB]) |
                       ((i_state==I_EXT2)     &  inst_ad[`SYMB]) |
                       ((i_state==I_EXT1)     & ~inst_as[`SYMB] &
                       ~(i_state_nxt==I_EXT2) &  inst_ad[`SYMB])   ? 16'hfffe : 16'h0000;

wire [15:0] ext_nxt  = ir + ext_incr;

// Store source extension word
reg [15:0] inst_sext;

`ifdef CLOCK_GATING
wire       inst_sext_en  = (decode & is_const)                 |
                           (decode & inst_type_nxt[`INST_JMP]) |
                           ((i_state==I_EXT1) & is_sext);
wire       mclk_inst_sext;
omsp_clock_gate clock_gate_inst_sext (.gclk(mclk_inst_sext),
                                      .clk (mclk), .enable(inst_sext_en), .scan_enable(scan_enable));
`else
wire       mclk_inst_sext = mclk;
`endif

always @(posedge mclk_inst_sext or posedge puc_rst)
  if (puc_rst)                                 inst_sext <= 16'h0000;
  else if (decode & is_const)                  inst_sext <= sconst_nxt;
  else if (decode & inst_type_nxt[`INST_JMP])  inst_sext <= {{5{ir[9]}},ir[9:0],1'b0};
`ifdef CLOCK_GATING
  else                                         inst_sext <= ext_nxt;
`else
  else if ((i_state==I_EXT1) & is_sext)        inst_sext <= ext_nxt;
`endif

// Source extension word is ready
wire inst_sext_rdy = (i_state==I_EXT1) & is_sext;


// Store destination extension word
reg [15:0] inst_dext;

`ifdef CLOCK_GATING
wire       inst_dext_en  = ((i_state==I_EXT1) & ~is_sext) |
                            (i_state==I_EXT2);
wire       mclk_inst_dext;
omsp_clock_gate clock_gate_inst_dext (.gclk(mclk_inst_dext),
                                      .clk (mclk), .enable(inst_dext_en), .scan_enable(scan_enable));
`else
wire       mclk_inst_dext = mclk;
`endif

always @(posedge mclk_inst_dext or posedge puc_rst)
  if (puc_rst)                           inst_dext <= 16'h0000;
  else if ((i_state==I_EXT1) & ~is_sext) inst_dext <= ext_nxt;
`ifdef CLOCK_GATING
  else                                   inst_dext <= ext_nxt;
`else
  else if  (i_state==I_EXT2)             inst_dext <= ext_nxt;
`endif

// Destination extension word is ready
wire inst_dext_rdy = (((i_state==I_EXT1) & ~is_sext) | (i_state==I_EXT2));


//=============================================================================
// 6)  DECODE INSTRUCTION
//=============================================================================

`ifdef CLOCK_GATING
wire       mclk_decode;
omsp_clock_gate clock_gate_decode (.gclk(mclk_decode),
                                   .clk (mclk), .enable(decode), .scan_enable(scan_enable));
`else
wire       mclk_decode = mclk;
`endif

//
// 6.1) OPCODE: INSTRUCTION TYPE
//----------------------------------------
// Instructions type is encoded in a one hot fashion as following:
//
// 3'b001: Single-operand arithmetic
// 3'b010: Conditional jump
// 3'b100: Two-operand arithmetic

reg  [2:0] inst_type;
assign     inst_type_nxt = {(ir[15:14]!=2'b00),
                            (ir[15:13]==3'b001),
                            (ir[15:13]==3'b000)} & {3{~irq_detect}};

always @(posedge mclk_decode or posedge puc_rst)
  if (puc_rst)      inst_type <= 3'b000;
`ifdef CLOCK_GATING
  else              inst_type <= inst_type_nxt;
`else
  else if (decode)  inst_type <= inst_type_nxt;
`endif

//
// 6.2) OPCODE: SINGLE-OPERAND ARITHMETIC
//----------------------------------------
// Instructions are encoded in a one hot fashion as following:
//
// 8'b00000001: RRC
// 8'b00000010: SWPB
// 8'b00000100: RRA
// 8'b00001000: SXT
// 8'b00010000: PUSH
// 8'b00100000: CALL
// 8'b01000000: RETI
// 8'b10000000: IRQ

reg   [7:0] inst_so;
wire  [7:0] inst_so_nxt = irq_detect ? 8'h80 : (one_hot8(ir[9:7]) & {8{inst_type_nxt[`INST_SO]}});

always @(posedge mclk_decode or posedge puc_rst)
  if (puc_rst)     inst_so <= 8'h00;
`ifdef CLOCK_GATING
  else             inst_so <= inst_so_nxt;
`else
  else if (decode) inst_so <= inst_so_nxt;
`endif

//
// 6.3) OPCODE: CONDITIONAL JUMP
//--------------------------------
// Instructions are encoded in a one hot fashion as following:
//
// 8'b00000001: JNE/JNZ
// 8'b00000010: JEQ/JZ
// 8'b00000100: JNC/JLO
// 8'b00001000: JC/JHS
// 8'b00010000: JN
// 8'b00100000: JGE
// 8'b01000000: JL
// 8'b10000000: JMP

reg   [2:0] inst_jmp_bin;
always @(posedge mclk_decode or posedge puc_rst)
  if (puc_rst)     inst_jmp_bin <= 3'h0;
`ifdef CLOCK_GATING
  else             inst_jmp_bin <= ir[12:10];
`else
  else if (decode) inst_jmp_bin <= ir[12:10];
`endif

wire [7:0] inst_jmp = one_hot8(inst_jmp_bin) & {8{inst_type[`INST_JMP]}};


//
// 6.4) OPCODE: TWO-OPERAND ARITHMETIC
//-------------------------------------
// Instructions are encoded in a one hot fashion as following:
//
// 12'b000000000001: MOV
// 12'b000000000010: ADD
// 12'b000000000100: ADDC
// 12'b000000001000: SUBC
// 12'b000000010000: SUB
// 12'b000000100000: CMP
// 12'b000001000000: DADD
// 12'b000010000000: BIT
// 12'b000100000000: BIC
// 12'b001000000000: BIS
// 12'b010000000000: XOR
// 12'b100000000000: AND

wire [15:0] inst_to_1hot = one_hot16(ir[15:12]) & {16{inst_type_nxt[`INST_TO]}};
wire [11:0] inst_to_nxt  = inst_to_1hot[15:4];

reg         inst_mov;
always @(posedge mclk_decode or posedge puc_rst)
  if (puc_rst)     inst_mov <= 1'b0;
`ifdef CLOCK_GATING
  else             inst_mov <= inst_to_nxt[`MOV];
`else
  else if (decode) inst_mov <= inst_to_nxt[`MOV];
`endif


//
// 6.5) SOURCE AND DESTINATION REGISTERS
//---------------------------------------

// Destination register
reg [3:0] inst_dest_bin;
always @(posedge mclk_decode or posedge puc_rst)
  if (puc_rst)     inst_dest_bin <= 4'h0;
`ifdef CLOCK_GATING
  else             inst_dest_bin <= ir[3:0];
`else
  else if (decode) inst_dest_bin <= ir[3:0];
`endif

wire  [15:0] inst_dest = cpu_halt_st          ? one_hot16(dbg_reg_sel) :
                         inst_type[`INST_JMP] ? 16'h0001               :
                         inst_so[`IRQ]  |
                         inst_so[`PUSH] |
                         inst_so[`CALL]       ? 16'h0002               :
                                                one_hot16(inst_dest_bin);


// Source register
reg [3:0] inst_src_bin;
always @(posedge mclk_decode or posedge puc_rst)
  if (puc_rst)     inst_src_bin <= 4'h0;
`ifdef CLOCK_GATING
  else             inst_src_bin <= ir[11:8];
`else
  else if (decode) inst_src_bin <= ir[11:8];
`endif

wire  [15:0] inst_src = inst_type[`INST_TO] ? one_hot16(inst_src_bin)  :
                        inst_so[`RETI]      ? 16'h0002                 :
                        inst_so[`IRQ]       ? 16'h0001                 :
                        inst_type[`INST_SO] ? one_hot16(inst_dest_bin) : 16'h0000;


//
// 6.6) SOURCE ADDRESSING MODES
//--------------------------------
// Source addressing modes are encoded in a one hot fashion as following:
//
// 13'b0000000000001: Register direct.
// 13'b0000000000010: Register indexed.
// 13'b0000000000100: Register indirect.
// 13'b0000000001000: Register indirect autoincrement.
// 13'b0000000010000: Symbolic (operand is in memory at address PC+x).
// 13'b0000000100000: Immediate (operand is next word in the instruction stream).
// 13'b0000001000000: Absolute (operand is in memory at address x).
// 13'b0000010000000: Constant 4.
// 13'b0000100000000: Constant 8.
// 13'b0001000000000: Constant 0.
// 13'b0010000000000: Constant 1.
// 13'b0100000000000: Constant 2.
// 13'b1000000000000: Constant -1.

reg [12:0] inst_as_nxt;

wire [3:0] src_reg = inst_type_nxt[`INST_SO] ? ir[3:0] : ir[11:8];

always @(src_reg or ir or inst_type_nxt)
  begin
     if (inst_type_nxt[`INST_JMP])
       inst_as_nxt =  13'b0000000000001;
     else if (src_reg==4'h3) // Addressing mode using R3
       case (ir[5:4])
         2'b11  : inst_as_nxt =  13'b1000000000000;
         2'b10  : inst_as_nxt =  13'b0100000000000;
         2'b01  : inst_as_nxt =  13'b0010000000000;
         default: inst_as_nxt =  13'b0001000000000;
       endcase
     else if (src_reg==4'h2) // Addressing mode using R2
       case (ir[5:4])
         2'b11  : inst_as_nxt =  13'b0000100000000;
         2'b10  : inst_as_nxt =  13'b0000010000000;
         2'b01  : inst_as_nxt =  13'b0000001000000;
         default: inst_as_nxt =  13'b0000000000001;
       endcase
     else if (src_reg==4'h0) // Addressing mode using R0
       case (ir[5:4])
         2'b11  : inst_as_nxt =  13'b0000000100000;
         2'b10  : inst_as_nxt =  13'b0000000000100;
         2'b01  : inst_as_nxt =  13'b0000000010000;
         default: inst_as_nxt =  13'b0000000000001;
       endcase
     else                    // General Addressing mode
       case (ir[5:4])
         2'b11  : inst_as_nxt =  13'b0000000001000;
         2'b10  : inst_as_nxt =  13'b0000000000100;
         2'b01  : inst_as_nxt =  13'b0000000000010;
         default: inst_as_nxt =  13'b0000000000001;
       endcase
  end
assign    is_const = |inst_as_nxt[12:7];

reg [7:0] inst_as;
always @(posedge mclk_decode or posedge puc_rst)
  if (puc_rst)     inst_as <= 8'h00;
`ifdef CLOCK_GATING
  else             inst_as <= {is_const, inst_as_nxt[6:0]};
`else
  else if (decode) inst_as <= {is_const, inst_as_nxt[6:0]};
`endif


// 13'b0000010000000: Constant 4.
// 13'b0000100000000: Constant 8.
// 13'b0001000000000: Constant 0.
// 13'b0010000000000: Constant 1.
// 13'b0100000000000: Constant 2.
// 13'b1000000000000: Constant -1.
always @(inst_as_nxt)
  begin
     if (inst_as_nxt[7])        sconst_nxt = 16'h0004;
     else if (inst_as_nxt[8])   sconst_nxt = 16'h0008;
     else if (inst_as_nxt[9])   sconst_nxt = 16'h0000;
     else if (inst_as_nxt[10])  sconst_nxt = 16'h0001;
     else if (inst_as_nxt[11])  sconst_nxt = 16'h0002;
     else if (inst_as_nxt[12])  sconst_nxt = 16'hffff;
     else                       sconst_nxt = 16'h0000;
  end


//
// 6.7) DESTINATION ADDRESSING MODES
//-----------------------------------
// Destination addressing modes are encoded in a one hot fashion as following:
//
// 8'b00000001: Register direct.
// 8'b00000010: Register indexed.
// 8'b00010000: Symbolic (operand is in memory at address PC+x).
// 8'b01000000: Absolute (operand is in memory at address x).

reg  [7:0] inst_ad_nxt;

wire [3:0] dest_reg = ir[3:0];

always @(dest_reg or ir or inst_type_nxt)
  begin
     if (~inst_type_nxt[`INST_TO])
       inst_ad_nxt =  8'b00000000;
     else if (dest_reg==4'h2)   // Addressing mode using R2
       case (ir[7])
         1'b1   : inst_ad_nxt =  8'b01000000;
         default: inst_ad_nxt =  8'b00000001;
       endcase
     else if (dest_reg==4'h0)   // Addressing mode using R0
       case (ir[7])
         1'b1   : inst_ad_nxt =  8'b00010000;
         default: inst_ad_nxt =  8'b00000001;
       endcase
     else                       // General Addressing mode
       case (ir[7])
         1'b1   : inst_ad_nxt =  8'b00000010;
         default: inst_ad_nxt =  8'b00000001;
       endcase
  end

reg [7:0] inst_ad;
always @(posedge mclk_decode or posedge puc_rst)
  if (puc_rst)     inst_ad <= 8'h00;
`ifdef CLOCK_GATING
  else             inst_ad <= inst_ad_nxt;
`else
  else if (decode) inst_ad <= inst_ad_nxt;
`endif


//
// 6.8) REMAINING INSTRUCTION DECODING
//-------------------------------------

// Operation size
reg       inst_bw;
always @(posedge mclk or posedge puc_rst)
  if (puc_rst)     inst_bw     <= 1'b0;
  else if (decode) inst_bw     <= ir[6] & ~inst_type_nxt[`INST_JMP] & ~irq_detect & ~cpu_halt_req;

// Extended instruction size
assign    inst_sz_nxt = {1'b0,  (inst_as_nxt[`IDX] | inst_as_nxt[`SYMB] | inst_as_nxt[`ABS] | inst_as_nxt[`IMM])} +
                        {1'b0, ((inst_ad_nxt[`IDX] | inst_ad_nxt[`SYMB] | inst_ad_nxt[`ABS]) & ~inst_type_nxt[`INST_SO])};
always @(posedge mclk_decode or posedge puc_rst)
  if (puc_rst)     inst_sz     <= 2'b00;
`ifdef CLOCK_GATING
  else             inst_sz     <= inst_sz_nxt;
`else
  else if (decode) inst_sz     <= inst_sz_nxt;
`endif


//=============================================================================
// 7)  EXECUTION-UNIT STATE MACHINE
//=============================================================================

// State machine registers
reg  [3:0] e_state;


// State machine control signals
//--------------------------------

wire src_acalc_pre =  inst_as_nxt[`IDX]   | inst_as_nxt[`SYMB]    | inst_as_nxt[`ABS];
wire src_rd_pre    =  inst_as_nxt[`INDIR] | inst_as_nxt[`INDIR_I] | inst_as_nxt[`IMM]  | inst_so_nxt[`RETI];
wire dst_acalc_pre =  inst_ad_nxt[`IDX]   | inst_ad_nxt[`SYMB]    | inst_ad_nxt[`ABS];
wire dst_acalc     =  inst_ad[`IDX]       | inst_ad[`SYMB]        | inst_ad[`ABS];
wire dst_rd_pre    =  inst_ad_nxt[`IDX]   | inst_so_nxt[`PUSH]    | inst_so_nxt[`CALL] | inst_so_nxt[`RETI];
wire dst_rd        =  inst_ad[`IDX]       | inst_so[`PUSH]        | inst_so[`CALL]     | inst_so[`RETI];

wire inst_branch   =  (inst_ad_nxt[`DIR] & (ir[3:0]==4'h0)) | inst_type_nxt[`INST_JMP] | inst_so_nxt[`RETI];

reg exec_jmp;
always @(posedge mclk or posedge puc_rst)
  if (puc_rst)                   exec_jmp <= 1'b0;
  else if (inst_branch & decode) exec_jmp <= 1'b1;
  else if (e_state==E_JUMP)      exec_jmp <= 1'b0;

reg exec_dst_wr;
always @(posedge mclk or posedge puc_rst)
  if (puc_rst)                exec_dst_wr <= 1'b0;
  else if (e_state==E_DST_RD) exec_dst_wr <= 1'b1;
  else if (e_state==E_DST_WR) exec_dst_wr <= 1'b0;

reg exec_src_wr;
always @(posedge mclk or posedge puc_rst)
  if (puc_rst)                                         exec_src_wr <= 1'b0;
  else if (inst_type[`INST_SO] & (e_state==E_SRC_RD))  exec_src_wr <= 1'b1;
  else if ((e_state==E_SRC_WR) || (e_state==E_DST_WR)) exec_src_wr <= 1'b0;

reg exec_dext_rdy;
always @(posedge mclk or posedge puc_rst)
  if (puc_rst)                exec_dext_rdy <= 1'b0;
  else if (e_state==E_DST_RD) exec_dext_rdy <= 1'b0;
  else if (inst_dext_rdy)     exec_dext_rdy <= 1'b1;

// Execution first state
wire [3:0] e_first_state = ~cpu_halt_st  & inst_so_nxt[`IRQ] ? E_IRQ_0  :
                            cpu_halt_req | (i_state==I_IDLE) ? E_IDLE   :
                            cpuoff                           ? E_IDLE   :
                            src_acalc_pre                    ? E_SRC_AD :
                            src_rd_pre                       ? E_SRC_RD :
                            dst_acalc_pre                    ? E_DST_AD :
                            dst_rd_pre                       ? E_DST_RD : E_EXEC;


// State machine
//--------------------------------

// States Transitions
always @(e_state       or dst_acalc     or dst_rd   or inst_sext_rdy or
         inst_dext_rdy or exec_dext_rdy or exec_jmp or exec_dst_wr   or
         e_first_state or exec_src_wr)
    case(e_state)
      E_IDLE   : e_state_nxt =  e_first_state;
      E_IRQ_0  : e_state_nxt =  E_IRQ_1;
      E_IRQ_1  : e_state_nxt =  E_IRQ_2;
      E_IRQ_2  : e_state_nxt =  E_IRQ_3;
      E_IRQ_3  : e_state_nxt =  E_IRQ_4;
      E_IRQ_4  : e_state_nxt =  E_EXEC;

      E_SRC_AD : e_state_nxt =  inst_sext_rdy     ? E_SRC_RD : E_SRC_AD;

      E_SRC_RD : e_state_nxt =  dst_acalc         ? E_DST_AD :
                                 dst_rd           ? E_DST_RD : E_EXEC;

      E_DST_AD : e_state_nxt =  (inst_dext_rdy |
                                 exec_dext_rdy)   ? E_DST_RD : E_DST_AD;

      E_DST_RD : e_state_nxt =  E_EXEC;

      E_EXEC   : e_state_nxt =  exec_dst_wr       ? E_DST_WR :
                                exec_jmp          ? E_JUMP   :
                                exec_src_wr       ? E_SRC_WR : e_first_state;

      E_JUMP   : e_state_nxt =  e_first_state;
      E_DST_WR : e_state_nxt =  exec_jmp          ? E_JUMP   : e_first_state;
      E_SRC_WR : e_state_nxt =  e_first_state;
    // pragma coverage off
      default  : e_state_nxt =  E_IRQ_0;
    // pragma coverage on
    endcase

// State machine
always @(posedge mclk or posedge puc_rst)
  if (puc_rst) e_state  <= E_IRQ_1;
  else         e_state  <= e_state_nxt;


// Frontend State machine control signals
//----------------------------------------

wire exec_done = exec_jmp        ? (e_state==E_JUMP)   :
                 exec_dst_wr     ? (e_state==E_DST_WR) :
                 exec_src_wr     ? (e_state==E_SRC_WR) : (e_state==E_EXEC);


//=============================================================================
// 8)  EXECUTION-UNIT STATE CONTROL
//=============================================================================

//
// 8.1) ALU CONTROL SIGNALS
//-------------------------------------
//
// 12'b000000000001: Enable ALU source inverter
// 12'b000000000010: Enable Incrementer
// 12'b000000000100: Enable Incrementer on carry bit
// 12'b000000001000: Select Adder
// 12'b000000010000: Select AND
// 12'b000000100000: Select OR
// 12'b000001000000: Select XOR
// 12'b000010000000: Select DADD
// 12'b000100000000: Update N, Z & C (C=~Z)
// 12'b001000000000: Update all status bits
// 12'b010000000000: Update status bit for XOR instruction
// 12'b100000000000: Don't write to destination

reg  [11:0] inst_alu;

wire        alu_src_inv   = inst_to_nxt[`SUB]  | inst_to_nxt[`SUBC] |
                            inst_to_nxt[`CMP]  | inst_to_nxt[`BIC] ;

wire        alu_inc       = inst_to_nxt[`SUB]  | inst_to_nxt[`CMP];

wire        alu_inc_c     = inst_to_nxt[`ADDC] | inst_to_nxt[`DADD] |
                            inst_to_nxt[`SUBC];

wire        alu_add       = inst_to_nxt[`ADD]  | inst_to_nxt[`ADDC]       |
                            inst_to_nxt[`SUB]  | inst_to_nxt[`SUBC]       |
                            inst_to_nxt[`CMP]  | inst_type_nxt[`INST_JMP] |
                            inst_so_nxt[`RETI];


wire        alu_and       = inst_to_nxt[`AND]  | inst_to_nxt[`BIC]  |
                            inst_to_nxt[`BIT];

wire        alu_or        = inst_to_nxt[`BIS];

wire        alu_xor       = inst_to_nxt[`XOR];

wire        alu_dadd      = inst_to_nxt[`DADD];

wire        alu_stat_7    = inst_to_nxt[`BIT]  | inst_to_nxt[`AND]  |
                            inst_so_nxt[`SXT];

wire        alu_stat_f    = inst_to_nxt[`ADD]  | inst_to_nxt[`ADDC] |
                            inst_to_nxt[`SUB]  | inst_to_nxt[`SUBC] |
                            inst_to_nxt[`CMP]  | inst_to_nxt[`DADD] |
                            inst_to_nxt[`BIT]  | inst_to_nxt[`XOR]  |
                            inst_to_nxt[`AND]  |
                            inst_so_nxt[`RRC]  | inst_so_nxt[`RRA]  |
                            inst_so_nxt[`SXT];

wire        alu_shift     = inst_so_nxt[`RRC]  | inst_so_nxt[`RRA];

wire        exec_no_wr    = inst_to_nxt[`CMP] | inst_to_nxt[`BIT];

wire [11:0] inst_alu_nxt  = {exec_no_wr,
                             alu_shift,
                             alu_stat_f,
                             alu_stat_7,
                             alu_dadd,
                             alu_xor,
                             alu_or,
                             alu_and,
                             alu_add,
                             alu_inc_c,
                             alu_inc,
                             alu_src_inv};

always @(posedge mclk_decode or posedge puc_rst)
  if (puc_rst)     inst_alu <= 12'h000;
`ifdef CLOCK_GATING
  else             inst_alu <= inst_alu_nxt;
`else
  else if (decode) inst_alu <= inst_alu_nxt;
`endif


endmodule // omsp_frontend
"""

omsp_clock_gate = """
module  omsp_clock_gate (

// OUTPUTs
    gclk,                      // Gated clock

// INPUTs
    clk,                       // Clock
    enable,                    // Clock enable
    scan_enable                // Scan enable (active during scan shifting)
);

// OUTPUTs
//=========
output         gclk;           // Gated clock

// INPUTs
//=========
input          clk;            // Clock
input          enable;         // Clock enable
input          scan_enable;    // Scan enable (active during scan shifting)


//=============================================================================
// CLOCK GATE: LATCH + AND
//=============================================================================

// Enable clock gate during scan shift
// (the gate itself is checked with the scan capture cycle)
wire    enable_in =   (enable | scan_enable);

// LATCH the enable signal
reg     enable_latch;
always @(clk or enable_in)
  if (~clk)
    enable_latch <= enable_in;

// AND gate
assign  gclk      =  (clk & enable_latch);


endmodule // omsp_clock_gate
"""

omsp_and_gate = """
module  omsp_and_gate (

// OUTPUTs
    y,                         // AND gate output

// INPUTs
    a,                         // AND gate input A
    b                          // AND gate input B
);

// OUTPUTs
//=========
output         y;              // AND gate output

// INPUTs
//=========
input          a;              // AND gate input A
input          b;              // AND gate input B


//=============================================================================
// 1)  SOME COMMENTS ON THIS MODULE
//=============================================================================
//
//    In its ASIC version, some combinatorial pathes of the openMSP430 are
// sensitive to glitches, in particular the ones generating the wakeup
// signals.
//    To prevent synthesis from optmizing combinatorial clouds into glitchy
// logic, this AND gate module has been instanciated in the critical places.
//
//    Make sure that synthesis doesn't ungroup this module. As an alternative,
// a standard cell from the library could also be directly instanciated here
// (don't forget the "dont_touch" attribute)
//
//
//=============================================================================
// 2)  AND GATE
//=============================================================================

assign  y  =  a & b;

endmodule // omsp_and_gate
"""

AutoSVA2_rules = f"""
RULES:
DO NOT declare properties; DECLARE assertions named as__<NAME>: assert property (<EXPRESSION>).
DO NOT use [] at the end of assertion NAME. Do not add @(posedge clk) to EXPRESSION.
DO NOT use foreach loops in assertions, use generate for.
Internal signals are those NOT present in the interface. Internal signals are declared within the module.
Referencing internal signals in the property file ALWAYS
requires prepending the name of the module before the signal name, e.g., name.<internal_signal>. &bitarray means that ALL the bits are ONES.
!(&bitarray) means it’s NOT TRUE that ALL the bits are ONES , i.e., SOME of the bits are ZEROS.
!(|bitarray) means that NONE of the bits are ONES, i.e., ALL the bits are ZEROS.
Signals ending in _reg are registers: the assigned value changes in the next cycle.
Signals NOT ending in _reg are wires: the assigned value changes in the same cycle.
USE a same-cycle assertion (|->) to reason about behavior occurring in the same cycle.
USE a next-cycle assertion (|=>) to reason about behavior occurring in the next cycle, for example, the updated value of a _reg.
DO NOT USE $past() in preconditions, ONLY in postconditions
DO NOT USE $past() on postcondition of same-cycle assertion
On the postcondition of next-cycle assertions (|=>), USE $past() to refer to the value of wires or a _reg on the cycle of the precondition.
On the postcondition of next-cycle assertions (|=>), DO NOT USE $past() to refer to the updated value of _reg.
"""

# AutoSVA is a tool that generates SVA assertions for RTL module transactions.
# The SVA assertions are written from the perspective of the RTL module that is the design-under-test (DUT).
# An RTL module has input and output signals in the module interface.
# Groups of signals in the module interface are called interfaces.
# Pairs of interfaces denote transactions: a transaction connects a request interface to a response interface.
# A request interface can be output by the DUT (outgoing transations), and so a response is expected to be received by the DUT eventually via an input reponse interface.
# A request interface can be an input to the DUT (incoming transations), and so a response is expected to be sent by the DUT eventually via an output reponse interface.
# AutoSVA requires annotations into the signal declaration section of the module interface to identify the interfaces and transactions.
# The annotations are written as a multi-line Verilog comment starting with /*AUTOSVA 
# A transation is defines as: transaction_name: request_interface -IN> response_interface if it's an incoming transaction. Thus the request interface is the input interface and the response interface is the output interface.
# A transation is alternatively defined as: transaction_name: request_interface -OUT> response_interface if it's an outgoing transaction. Thus the request interface is the output interface and the response interface is the input interface.
# For example, the following FIFO module interface has an incoming transaction called fifo_transaction: push -IN> pop
# module fifo (
# input  wire             push_val,
# output wire             push_rdy,
# input  wire [WIDTH-1:0] push_payload,
# output wire             pop_val,
# input  wire             pop_rdy,
# output wire [WIDTH-1:0] pop_payload
# );
# and so the AUTOSVA annotation is:
# /*AUTOSVA
# fifo_transaction: push -IN> pop
#                     push_valid = push_val
#                     push_ready = push_rdy
# [WIDTH-1:0]         push_data = push_payload
# [INFLIGHT_IDX-1:0]  push_transid = fifo.write_pointer
#                     pop_valid = pop_val
#                     pop_ready = pop_rdy
# [WIDTH-1:0]         pop_data = pop_payload
# [INFLIGHT_IDX-1:0]  pop_transid = fifo.read_pointer

# NOTE that in addition to the fifo_transaction: push -IN> pop there are more annotations that match interface signals with interface atributes.
# Both request and response interfaces have valid, ready, data and transid attributes.
# Valid indicates that the request or response is valid, and can be acknowledged by the other side.
# Ready indicates that the request or response is ready to be received by the other side.
# Data is the payload of the request or response.
# Transid is a unique identifier of the request or response.

# The formalized syntax of the AUTOSVA annotation is:
# TRANSACTION ::= TNAME: RELATION ATTRIB
# RELATION ::= P −in> Q | P −out> Q
# ATTRIB ::= ATTRIB, ATTRIB | SIG = ASSIGN | input SIG | outputSIG
# SIG ::= [STR:0] FIELD | STR FIELD
# FIELD ::= P SUFFIX | Q SUFFIX
# SUFFIX ::= val | ack | transid | transid unique | active | stable | data
# TNAME, P, Q ::= STR

# YOU MUST LEARN THE RULES ABOVE, THEN ANALYZE the RTL module interface and implementation and WRITE AUTOSVA annotations.
# DO NOT answer anything except for the annotations.