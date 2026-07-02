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
from types import SimpleNamespace
from pathlib import Path
from utils import get_user, get_host
from collections import OrderedDict
from datetime import datetime
import json
import os
import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from FVEval.fv_eval import (
    prompts_nl2sva_machine,
    prompts_nl2sva_human,
    utils,
)

# Select one execution stage: train / inference / eval.
# global_task = 'inference'
global_task = 'train'
# global_task = 'eval'

ROOT = Path(__file__).resolve().parents[1]
LOG_ROOT = ROOT / "src" / "logs"
DEFAULT_TRAIN_LOGDIR = os.environ.get(
    "FVRULELEARNER_TRAIN_LOGDIR",
    str(LOG_ROOT / "train_your_run_here"),
)
DEFAULT_EVAL_LOGDIR = os.environ.get(
    "FVRULELEARNER_EVAL_LOGDIR",
    str(LOG_ROOT / "inference_your_run_here"),
)
# debug = False
debug = True

# Debug-only: restrict the training pool used by retrieval/Q-Tree building.
# Leave empty for normal release runs.
# Example: training_cases = [0, 1, 2, 3]
training_cases = [0,1,2,3]

# Supported release tasks:
# task = "nl2sva_human"
task = "nl2sva_machine"
# task = "nl2sva_opencore"

LLM_gateaway = "openai"
# LLM_gateaway = "claude"

llm_model = 'gpt-4o'
# llm_model = "claude-sonnet-4-5-20250929"

llm_mode = 'agent'
# llm_mode = 'baseline'

if global_task in ['inference', 'train']:
    model = 'agent'
    src_examples = [task]

    if "nl2sva" not in task:
        raise ValueError(f"Unsupported release task: {task}")

    num_assertions = 1

    # Keep the current mainline agent orchestration.
    agent_arch = "flexible_agents"

    # Maximum retries for syntax repair on a single sample.
    max_num_syntax_iter = 10

    # Core LLM generation parameters.
    temperature = 0
    cleanup_temp = True
    # Number of in-context examples prepended to the prompt.
    num_icl = 3
    # Upper bound for model output tokens per response.
    max_token = 20000
    # Optional dataset partitioning for batched local runs.
    group_id = 0
    num_group = 1
    start_num = 0

    # Train/test split used when sampling internal train/inference subsets.
    if "nl2sva" in task:
        split_ratios = {
            'test': 0.2,
            'train': 0.8,
        }

    random_seed = 100

    # Use the full saved Q-Tree pool by default.
    qtree_subsample_ratio = split_ratios['train']

    if task in src_examples:
        filter_self = False
        # filter_self = True

    # Enable JasperGold-backed checking when available.
    use_JG = True

    GPT_retries = 10
    backoff_factor = 2

    if global_task == 'train' and 'nl2sva' in task:
        # Training builds suggestions / Q-Trees; retrieval is disabled here.
        use_RAG = False
        use_JG = False
        RAG_content = ['Suggestions']
        # Number of self-improvement iterations per training sample.
        num_iter = 2

        is_constrain_number = False

        suggestion_saving_rule = "none"
        train_temp_setting = "random"
        if train_temp_setting == "random":
            change_only_bleu_same = True
            low_temp = 0
            high_temp = 1.0
        if debug == True:
            num_iter = 2

        use_QTree = True
        if use_QTree:
            # Number of questions expanded per Q-Tree level.
            question_tree_width = 3
        
        PEC_method = 'JasperGold'
        only_BLEU = False

        carryover = False
        if carryover == True:
            num_carryover = 1

    elif global_task == 'inference' and 'nl2sva' in task:
        use_RAG = True
        similarity_str = ["Question"]
        eval_content = ["similarity","jg"]

        # Optional ensemble baseline for inference.
        baseline_emsemble = False

        if baseline_emsemble:
            use_RAG = False
            passk = 10
            voting_tech = "LLM"
        if use_RAG:
            RAG_content = ['Examples', 'Suggestions']

            all_examples = False

            if 'Examples' in RAG_content:
                prompting_instruction = 0
                Examples_top_k = 1

            if 'Suggestions' in RAG_content:
                # Number of retrieved suggestion traces/rules to use.
                Suggestions_top_k = 3

                # Use retrieved Q-Tree guidance directly instead of a separate
                # suggestions-reasoning agent.
                Suggestions_Reasoning = False

                # Enable FVRuleLearner's Q-Tree-enhanced retrieval.
                retrieval_on_ranking = True
                if retrieval_on_ranking:
                    # Number of similar Q-Trees retrieved before ranking.
                    qtree_similarity_top_k = 5
                    qtree_ranking_mode = 'prompt' 
                    # Generate ranked rules instead of directly reusing retrieved ones.
                    rule_source = 'generate'

                    llm_score_weight = 0.5
                    operator_score_weight = 0.5
                    
                    # Keep all non-zero operator-alignment matches.
                    operator_pruning_threshold = 0.0
                    
                    instruct_skip_misaligned_in_rules = True

                deduplication = True
                operator_explanation = False
                filter_functionality = True
                retrieve_str = ["Suggestions"]
                # Point this to a previously generated train log directory.
                # You can override it with the FVRULELEARNER_TRAIN_LOGDIR environment variable.
                load_suggestions_path = DEFAULT_TRAIN_LOGDIR

    if task == "nl2sva_human":
        dataset_path = os.path.join(ROOT, "FVEval", "data_nl2sva", "data", "nl2sva_human.csv")
    elif task == "nl2sva_machine":
        dataset_path = os.path.join(ROOT, "FVEval", "data_nl2sva", "data", "nl2sva_machine.csv")
    elif task == "nl2sva_opencore":
        dataset_path = os.path.join(ROOT, "FVEval", "data_1k", "module_sva_nl_manual_editing.csv")
    else:
        raise ValueError(f"Unsupported release task: {task}")

    timestamp_str = datetime.now().strftime("%Y%m%d%H%M")
    save_dir = ROOT / f"results_nl2sva/{num_icl}/{timestamp_str}"
    save_dir = save_dir.as_posix()

    if debug == True:
        # Debug mode only runs a tiny subset for smoke testing.
        random_sample_size = 1
        cleanup_temp_files = False
        # Restrict inference/eval to selected dataset row indices.
        # Example: only_test_ids = [4]
        only_test_ids = [4]

        suggestions_effectiveness_csv_path = None
    else:
        random_sample_size = -1
        cleanup_temp_files = False

elif global_task == 'eval':
    # Point this to an existing inference log directory when re-running eval only.
    # You can override it with the FVRULELEARNER_EVAL_LOGDIR environment variable.
    folder_to_eval = DEFAULT_EVAL_LOGDIR

else:
    raise NotImplementedError()

if global_task == 'inference' or global_task == 'eval' or global_task == 'train':
    nparallel = 1
    if debug == True:
        nparallel = 1
    if global_task == 'eval':
        eval_content = ["similarity","jg"]
    if task == "nl2sva_machine":
        tcl_file_path = os.path.join(ROOT, "FVEval", "tool_scripts", "run_jg_only_analysis.tcl")
        tcl_eval_file_path = os.path.join(ROOT, "FVEval", "tool_scripts", "run_jg_nl2sva_machine.tcl")
    elif task == "nl2sva_human":
        tcl_file_path = os.path.join(ROOT, "FVEval", "tool_scripts", "run_jg_only_analysis.tcl")
        tcl_eval_file_path = os.path.join(ROOT, "FVEval", "tool_scripts", "run_jg_nl2sva_human.tcl")
    elif task == "nl2sva_opencore":
        tcl_file_path = os.path.join(ROOT, "FVEval", "tool_scripts", "run_jg_only_syntax_opencore.tcl")
        tcl_eval_file_path = os.path.join(ROOT, "FVEval", "tool_scripts", "run_jg_nl2sva_opencore.tcl")
    else:
        raise ValueError(f"Unsupported release task: {task}")

user = get_user()
hostname = get_host()

###################################### Below: repository metadata ######################################

try:
    import git
except Exception as e:
    raise type(e)(f'{e}\nRun pip install gitpython or\nconda install gitpython')
try:
    repo = git.Repo(ROOT)
    commit_sha = repo.head.object.hexsha
except git.exc.InvalidGitRepositoryError as e:
    raise Exception(f"Invalid Git repository at {ROOT}") from e

vars = OrderedDict(vars())
FLAGS = OrderedDict()
for k, v in vars.items():
    if not k.startswith('__') and type(v) in [
        int,
        float,
        str,
        list,
        dict,
        type(None),
        bool,
    ]:
        FLAGS[k] = v
FLAGS = SimpleNamespace(**FLAGS)