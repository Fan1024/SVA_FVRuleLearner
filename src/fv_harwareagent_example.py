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
from rag_agent import RAGAgent  # Import the RAGAgent class
# from utils_agent import initiate_chat_with_retry

import os
import re
import sys
from tqdm import tqdm
import random
import pandas as pd
from dataclasses import dataclass
import pickle
from dataclasses import asdict
import time
from types import SimpleNamespace

# Add the path to the fv_eval directory to sys.path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', 'fv_eval')))
# Add the project root directory to sys.path for hardware_agent imports
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from hardware_agent.tools_utility import get_tools_descriptions, create_tool_tbl
from hardware_agent.examples.react_prompt import PREFIX, FORMAT_INSTRUCTIONS, SUFFIX

from langchain_core.prompts import PromptTemplate
from hardware_agent.examples.fv_question import system_prompt
from pprint import pformat

from config import FLAGS
from saver import saver
from utils_agent import initiate_chat_with_retry

# import the functions from fv_eval
# from benchmark_launcher import BenchmarkLauncher
from FVEval.fv_eval import benchmark_launcher

from FVEval.fv_eval import prompts_svagen_nl2sva as prompts_svagen_nl2sva
from FVEval.fv_eval.data import InputData, LMResult
from FVEval.fv_eval import utils as utils2

from pathlib import Path
from collections import OrderedDict
from fv_tools import evaluate_jg

from FVEval.fv_eval import (
    prompts_nl2sva_machine,
    prompts_nl2sva_human,
    utils,
)

print = saver.log_info

class RateLimitError(Exception):
    pass

class FVProcessor:
    def __init__(self):
        self.dataset_path = FLAGS.dataset_path
        # self.dataset = self.load_dataset(self.dataset_path)
        self.model_name = FLAGS.llm_model
        self.agent_arch = FLAGS.agent_arch
        self.num_icl_examples = FLAGS.num_icl
        self.debug = FLAGS.debug
        self.save_dir = FLAGS.save_dir
        self.experiment_id = self.dataset_path.split(".csv")[0].split("/")[-1]

        # Initialize RAGAgent with a list of documents
        self.example_rag_agent = None
        self.suggestion_rag_agent = None
        self.assertion_generator = None
        if FLAGS.global_task == 'train':  # learning/training

            # assert FLAGS.RAG_content == ['Suggestions']
            # if FLAGS.RAG_content == ['Suggestions']:

            self.train_launcher = OrderedDict()
            for task in FLAGS.src_examples:
                # and 'Examples' in FLAGS.RAG_content:
                bmark_launcher_src = self._create_bmark_launcher(task)
                # bmark_launcher_src.run(...) # internally saving knwoledge to saver
                self.train_launcher[task] = bmark_launcher_src

                # Finished looping through all data.
                # saver.dump_knolwedge_to_disk()

            # else:
            #     raise NotImplementedError(f"RAG_content {FLAGS.RAG_content} is not implemented.")
        elif FLAGS.global_task == 'inference':
            self.bmark_launcher = self._create_bmark_launcher(FLAGS.task)
        # else:
        #     FLAGS.global_task == 'eval'

        if 'nl2sva' in FLAGS.task:
            if FLAGS.use_RAG:
                assert FLAGS.global_task == 'inference'
                delimiter = "<---->"

                if 'Examples' in FLAGS.RAG_content:
                    # Define training IDs (examples that should be in the RAG pool)
                    # These are hardcoded to prevent data leakage from test set
                    # Check if debug mode is enabled and training_cases is specified
                    if FLAGS.debug and hasattr(FLAGS, 'training_cases') and FLAGS.training_cases:
                        print(f"DEBUG MODE: Using custom training_cases for Examples: {FLAGS.training_cases}")
                        training_IDs = FLAGS.training_cases
                    elif FLAGS.task == "nl2sva_human":
                        training_IDs = [73, 28, 65, 36, 16, 59, 42, 47, 32, 45, 60, 4, 34, 20, 37, 61, 69, 1, 46, 54, 43, 72, 48, 0, 56, 7, 51, 41, 67, 24, 17, 35, 29, 25, 57, 63, 40, 23, 75, 12, 9, 11, 13, 49, 53, 19, 70, 21, 26, 6, 33, 76, 10, 15, 68, 14, 64, 55, 44, 50, 22, 77, 58, 18]
                    elif FLAGS.task == "nl2sva_machine":
                        training_IDs = [7, 243, 8, 136, 227, 130, 190, 148, 58, 146, 120, 277, 84, 27, 226, 57, 77, 127, 22, 169, 137, 156, 110, 143, 20, 18, 295, 261, 252, 88, 119, 108, 239, 93, 282, 257, 238, 162, 45, 241, 271, 265, 80, 297, 142, 268, 118, 28, 10, 213, 1, 51, 212, 244, 71, 133, 197, 4, 170, 101, 231, 0, 34, 275, 187, 6, 181, 48, 249, 66, 147, 68, 19, 105, 175, 274, 106, 290, 294, 199, 184, 298, 115, 160, 109, 234, 154, 283, 17, 222, 31, 23, 54, 35, 167, 285, 40, 248, 50, 161, 200, 215, 288, 113, 9, 139, 122, 164, 168, 246, 38, 230, 26, 99, 11, 53, 195, 245, 264, 49, 258, 29, 240, 3, 116, 260, 279, 145, 186, 224, 55, 254, 286, 79, 291, 152, 12, 251, 30, 178, 287, 70, 269, 250, 42, 262, 211, 173, 14, 37, 65, 149, 126, 205, 131, 196, 223, 242, 180, 210, 216, 61, 255, 111, 166, 76, 25, 208, 15, 194, 102, 123, 266, 218, 138, 87, 174, 135, 86, 151, 176, 299, 182, 129, 237, 256, 281, 183, 267, 155, 292, 247, 193, 270, 159, 64, 198, 229, 121, 13, 85, 98, 83, 75, 202, 2, 92, 63, 82, 192, 141, 236, 206, 107, 209, 189, 177, 96, 72, 91, 284, 158, 117, 171, 104, 24, 134, 233, 41, 62, 272, 56, 259, 221, 179, 201, 89, 232, 235, 74]
                    elif FLAGS.task == "nl2sva_opencore":
                        training_IDs = [885, 748, 832, 349, 134, 770, 642, 462, 715, 278, 8, 989, 857, 763, 189, 478, 654, 357, 499, 6, 882, 517, 629, 577, 227, 631, 338, 644, 186, 247, 515, 347, 965, 284, 373, 761, 445, 634, 475, 693, 18, 529, 309, 163, 181, 806, 894, 140, 430, 967, 732, 387, 799, 891, 764, 290, 439, 377, 960, 956, 60, 500, 191, 362, 751, 875, 289, 456, 393, 671, 354, 547, 954, 572, 218, 847, 374, 15, 460, 680, 153, 248, 736, 145, 117, 403, 397, 560, 508, 417, 239, 241, 203, 75, 172, 869, 297, 591, 743, 226, 473, 80, 52, 135, 942, 724, 541, 414, 673, 408, 729, 809, 595, 897, 302, 497, 868, 176, 432, 431, 695, 603, 25, 138, 527, 107, 204, 267, 993, 726, 814, 943, 999, 183, 304, 319, 556, 70, 523, 130, 210, 716, 336, 190, 787, 17, 917, 995, 801, 888, 668, 434, 803, 848, 479, 179, 834, 575, 187, 502, 467, 559, 315, 938, 265, 395, 136, 194, 649, 114, 873, 58, 866, 910, 900, 392, 657, 881, 10, 29, 261, 643, 696, 292, 285, 879, 398, 909, 549, 514, 449, 613, 794, 268, 940, 587, 583, 755, 535, 565, 386, 588, 73, 984, 985, 628, 701, 733, 484, 56, 205, 851, 886, 586, 146, 627, 105, 72, 930, 64, 270, 959, 325, 250, 229, 406, 101, 415, 589, 625, 367, 420, 438, 4, 490, 740, 0, 539, 660, 552, 538, 708, 382, 711, 404, 126, 429, 507, 970, 828, 618, 608, 169, 928, 506, 855, 207, 975, 363, 919, 564, 597, 802, 624, 323, 825, 876, 314, 528, 728, 520, 840, 93, 159, 796, 842, 481, 918, 21, 451, 585, 350, 283, 320, 394, 962, 142, 573, 892, 476, 769, 607, 141, 544, 421, 551, 714, 947, 950, 368, 606, 41, 482, 137, 493, 774, 878, 682, 206, 119, 501, 971, 383, 739, 294, 719, 616, 352, 487, 279, 46, 416, 973, 762, 494, 286, 19, 983, 251, 78, 570, 812, 99, 511, 252, 418, 578, 883, 348, 933, 924, 816, 332, 372, 407, 295, 826, 264, 42, 364, 76, 858, 510, 271, 635, 345, 477, 22, 413, 244, 530, 219, 379, 678, 173, 626, 758, 95, 425, 652, 180, 600, 246, 582, 28, 853, 782, 401, 409, 686, 222, 259, 272, 601, 944, 446, 199, 690, 390, 435, 62, 509, 746, 7, 650, 835, 905, 43, 856, 936, 531, 996, 16, 805, 850, 156, 274, 321, 647, 322, 697, 83, 433, 620, 157, 611, 798, 160, 687, 333, 196, 448, 312, 313, 672, 896, 122, 328, 375, 703, 849, 11, 474, 238, 705, 40, 747, 109, 795, 845, 619, 30, 262, 602, 760, 702, 504, 968, 829, 522, 990, 489, 920, 646, 480, 707, 91, 561, 115, 518, 230, 14, 35, 234, 356, 232, 288, 483, 118, 330, 496, 661, 951, 388, 691, 366, 174, 931, 797, 741, 813, 880, 580, 977, 780, 718, 300, 90, 108, 492, 158, 937, 20, 426, 452, 47, 71, 89, 359, 440, 469, 992, 777, 228, 630, 592, 710, 128, 308, 895, 113, 516, 738, 598, 887, 139, 648, 468, 640, 74, 884, 562, 590, 615, 824, 217, 200, 457, 391, 389, 994, 941, 964, 327, 720, 13, 907, 3, 713, 162, 147, 953, 360, 632, 709, 756, 85, 188, 745, 34, 454, 689, 331, 361, 948, 88, 23, 961, 838, 830, 659, 305, 864, 81, 669, 9, 957, 237, 301, 571, 932, 38, 311, 921, 2, 277, 839, 987, 233, 195, 97, 727, 266, 836, 275, 612, 79, 422, 213, 148, 427, 808, 593, 621, 198, 536, 997, 870, 906, 461, 821, 436, 553, 37, 901, 750, 704, 68, 257, 125, 92, 656, 216, 143, 827, 96, 161, 254, 202, 48, 773, 485, 817, 50, 949, 455, 717, 39, 558, 488, 658, 675, 916, 155, 730, 694, 410, 106, 742, 399, 44, 214, 865, 737, 121, 862, 841, 935, 486, 116, 911, 12, 981, 341, 365, 581, 744, 766, 823, 666, 221, 636, 537, 317, 224, 609, 800, 51, 735, 123, 712, 889, 281, 771, 55, 168, 334, 599, 692, 59, 150, 260, 596, 505, 820, 525, 785, 447, 913, 723, 843, 867, 245, 258, 444, 667, 307, 103, 833, 63, 779, 411, 495, 371, 874, 555, 351, 698, 540, 346, 604, 706, 296, 731, 988, 793, 633, 734, 253, 623, 53, 775, 567, 638, 129, 396, 923, 946, 818, 458, 242, 681, 26, 861, 171, 197, 166, 579, 871, 792, 151, 405, 617, 5, 184, 127, 653, 664, 877, 164, 384, 837, 811, 922, 282, 568, 472, 412, 215, 854, 419, 641, 378, 355, 914, 193, 144, 182, 208, 786, 859, 316, 235, 343, 209, 969, 663, 955, 674, 49, 269, 466, 754, 82, 124, 545, 112, 819, 519, 443, 358, 749, 402, 722, 178, 789, 974, 465, 470, 149]

                    documents = []
                    for src in FLAGS.src_examples:
                        # Get the correct dataset path for this source
                        dataset_path = FLAGS.dataset_path
                        # print(f"@@@DEBUG: Loading examples from source '{src}': {dataset_path}")
                        df = pd.read_csv(dataset_path)
                        # print(f"@@@DEBUG: CSV has {len(df)} total rows")
                        # print(f"@@@DEBUG: Will load {len(training_IDs)} training rows: {training_IDs[:5]}...")

                        # Load ONLY the specific training row IDs from CSV
                        loaded_count = 0
                        for csv_row_id in training_IDs:
                            if csv_row_id >= len(df):
                                print(f"@@@WARNING: csv_row_id={csv_row_id} out of bounds (CSV has {len(df)} rows)")
                                continue
                            
                            row = df.iloc[csv_row_id]  # Get row by ACTUAL CSV position
                            prompt = str(row['prompt'] if 'prompt' in row else '').strip()
                            ref_solution = str(row['ref_solution'] if 'ref_solution' in row else '').strip()
                            
                            if prompt and ref_solution:
                                RAG_string = f'Question: Create a SVA assertion that checks: {prompt}{delimiter}Reference Answer: {ref_solution}\n'
                                documents.append(RAG_string)
                                loaded_count += 1
                                
                        # print(f"@@@DEBUG: Successfully loaded {loaded_count} training examples from {src}")

                    # Define the pickle file name
                    pkl_filename = os.path.join(saver.logdir, "examples.pkl")

                    # Save documents to the pickle file
                    with open(pkl_filename, "wb") as pkl_file:
                        pickle.dump(documents, pkl_file)
                    # print(f'@@@SUMMARY: Loaded {len(documents)} training examples for RAG')
                    # print(f'@@@SUMMARY: Training set: {len(training_IDs)} IDs, Test set excluded: {FLAGS.only_test_ids if hasattr(FLAGS, "only_test_ids") else "N/A"}')
                    # print(f'@@@SUMMARY: First 2 examples:')
                    
                    assert len(documents) > 0, f"No training examples loaded! Check training_IDs and dataset_path"
                    assert len(documents) == len(training_IDs), f"Expected {len(training_IDs)} documents but got {len(documents)}"
                    
                    # breakpoint()

                    for doc_id, doc in enumerate(documents[0:3]):
                        print(f'\t: {doc_id} {doc}')
                    assert len(documents) > 0
                    self.example_rag_agent = RAGAgent(documents=documents, rag_type='Examples', embedding_model='sbert')

                if 'Suggestions' in FLAGS.RAG_content:
                    # if FLAGS.suggestion_link == "Direct":
                    # Try both possible file names
                    suggestions_file = os.path.join(FLAGS.load_suggestions_path, 'suggestions.pkl')
                    all_suggestions_file = os.path.join(FLAGS.load_suggestions_path, 'all_suggestions.pkl')
                    
                    if os.path.exists(suggestions_file):
                        with open(suggestions_file, "rb") as pkl_file:
                            documents = pickle.load(pkl_file)
                    elif os.path.exists(all_suggestions_file):
                        with open(all_suggestions_file, "rb") as pkl_file:
                            documents = pickle.load(pkl_file)
                    else:
                        raise FileNotFoundError(
                            "Neither 'suggestions.pkl' nor 'all_suggestions.pkl' was found in "
                            f"{FLAGS.load_suggestions_path}. "
                            "Set 'load_suggestions_path' in src/config.py to a real training log directory, "
                            "or export FVRULELEARNER_TRAIN_LOGDIR to override it."
                        )
                    
                    # print(f'Loaded {len(documents)} suggestions:\n{pformat(documents[:2])}')
                    # elif FLAGS.suggestion_link == "Associated":
                    #     with open(FLAGS.load_suggestions_path, "rb") as pkl_file:
                    #         documents = pickle.load(pkl_file)
                    #         print(f'Loaded {len(documents)} suggestions:\n{pformat(documents)}')
                    # else:
                    #     raise NotImplementedError()
                    assert len(documents) > 0
                    self.suggestion_rag_agent = RAGAgent(documents=documents, rag_type='Suggestions', embedding_model='sbert')

    def _build_lightweight_agents(self):
        agents = {}
        for agent_cfg in getattr(self, "agent_configs", []):
            base_cfg = agent_cfg.get("base_agent_config", {})
            name = base_cfg.get("name")
            if not name:
                continue
            agents[name] = SimpleNamespace(
                name=name,
                system_message=base_cfg.get("system_message", ""),
                llm_config=base_cfg.get("llm_config", {}),
                stats={"runtime": [], "tokens": []},
            )
        return agents

    def _run_lightweight_nl2sva(self, agents, system_prompt, fv_prompt, row):
        if "Coding" not in agents or "user" not in agents:
            raise RuntimeError("Lightweight path requires 'user' and 'Coding' agents.")

        agents["Coding"].system_message = system_prompt
        message = fv_prompt
        response = None

        if getattr(FLAGS, "use_RAG", False):
            full_question = f"Question: Create a SVA assertion that checks: {row.prompt}"

            if (
                self.example_rag_agent is not None
                and "Examples" in getattr(FLAGS, "RAG_content", [])
            ):
                retrieved_docs = self.example_rag_agent.retrieve(
                    full_question,
                    top_k=getattr(FLAGS, "Examples_top_k", 1),
                )
                examples_list = [f"- {doc}\n" for doc in retrieved_docs]
                if getattr(FLAGS, "prompting_instruction", 0) == 0:
                    message = (
                        f"{message}\n\n"
                        "Additional context from similar documents:\n"
                        + "".join(examples_list)
                    )
                elif getattr(FLAGS, "prompting_instruction", 0) == 1:
                    message = (
                        f"{message}\n\n"
                        "Use the following SVA assertion examples to understand the structure and logic of similar assertions. "
                        "Pay attention to how conditions and logical operators are used to form the assertions. "
                        "Based on this understanding, generate the requested SVA assertion accurately.\n"
                        + "".join(examples_list)
                    )

            if (
                self.suggestion_rag_agent is not None
                and "Suggestions" in getattr(FLAGS, "RAG_content", [])
            ):
                retrieved_result = self.suggestion_rag_agent.retrieve(
                    full_question,
                    top_k=getattr(FLAGS, "Suggestions_top_k", 3),
                    testbench=row.testbench,
                )

                operator_explanations = {}
                initial_sva = None
                if isinstance(retrieved_result, dict):
                    retrieved_docs = retrieved_result.get("suggestions", [])
                    initial_sva = retrieved_result.get("initial_sva")
                    operator_explanations = retrieved_result.get("operator_explanations", {})
                else:
                    retrieved_docs = retrieved_result

                if len(retrieved_docs) == 0 and initial_sva and not getattr(FLAGS, "operator_explanation", False):
                    saver.save_stats("used_suggestions", 0)
                    return initial_sva

                suggestions_list = []
                seen_suggestions = set()
                for doc in retrieved_docs:
                    cleaned_doc = re.sub(r"^Suggestions:\s*", "", str(doc).strip())
                    for suggestion in cleaned_doc.split("\n"):
                        suggestion = suggestion.strip()
                        if not suggestion:
                            continue
                        if getattr(FLAGS, "deduplication", True):
                            if suggestion in seen_suggestions:
                                continue
                            seen_suggestions.add(suggestion)
                        suggestions_list.append(suggestion)

                appended_suggestions = "\n".join(suggestions_list)
                if appended_suggestions:
                    saver.save_stats("used_suggestions", 1)
                    message = (
                        f"{message}\n\n"
                        "Additional knowledge/suggestions to follow/obey:\n"
                        f"{appended_suggestions}"
                    )
                else:
                    saver.save_stats("used_suggestions", 0)

                if getattr(FLAGS, "operator_explanation", False) and operator_explanations:
                    message += "\n\nAdditional background information about operators:\n"
                    for operator, explanation in operator_explanations.items():
                        message += f"Operator: {operator}\nExplanation: {explanation}\n"

        if FLAGS.debug:
            print(f"enriched_prompt=\n{message}")

        response = initiate_chat_with_retry(
            agents["user"],
            agents["Coding"],
            message=message,
        )
        return response

    def _create_bmark_launcher(self, task):
        # dataset_path for self-learning source files
        ROOT = Path(__file__).resolve().parents[1]
        dataset_path_for_learning = {
            "nl2sva_human": os.path.join(ROOT, "FVEval", "data_nl2sva", "data", "nl2sva_human.csv"),
            # "nl2sva_machine": os.path.join(ROOT, "FVEval", "data_nl2sva", "data", "nl2sva_machine.csv"),
            "nl2sva_machine": os.path.join(ROOT, "FVEval", "data_nl2sva", "data", "nl2sva_machine.csv"),
            "nl2sva_opencore": os.path.join(ROOT, "FVEval", "data_1k", "module_sva_nl_manual_editing.csv"),
        }
        if task == "nl2sva_human":
            bmark_launcher = benchmark_launcher.NL2SVAHumanLauncher(
                save_dir=saver.logdir,
                dataset_path=dataset_path_for_learning.get(task),
                task="nl2sva_human",
                model_name_list=[FLAGS.llm_model],
                num_icl_examples=FLAGS.num_icl,
                debug=FLAGS.debug,
                FVProcessor=self,
            )
        elif task == "nl2sva_machine":
            bmark_launcher = benchmark_launcher.NL2SVAMachineLauncher(
                save_dir=saver.logdir,
                dataset_path=dataset_path_for_learning.get(task),
                task="nl2sva_machine",
                model_name_list=[FLAGS.llm_model],
                num_icl_examples=FLAGS.num_icl,
                debug=FLAGS.debug,
                FVProcessor=self,
            )
        elif task == "nl2sva_opencore":
            bmark_launcher = benchmark_launcher.NL2SVAMachineLauncher(
                save_dir=saver.logdir,
                dataset_path=dataset_path_for_learning.get(task),
                task="nl2sva_opencore",
                model_name_list=[FLAGS.llm_model],
                num_icl_examples=FLAGS.num_icl,
                debug=FLAGS.debug,
                FVProcessor=self,
            )
        else:
            print(f"Unsupported eval mode")
            raise NotImplementedError
        return bmark_launcher

    def process_agents(self, config_list, evaluate_jg):
        if FLAGS.agent_arch == "three_agents" or FLAGS.agent_arch == "four_agents":
            self.add_helper_agents(config_list)

        if FLAGS.agent_arch == "four_agents":
            self.add_jaspergold_agent(config_list, evaluate_jg)

        if FLAGS.agent_arch == "flexible_agents":
            if FLAGS.global_task == 'train':
                self.add_RAG_reflection_agent(config_list)
            else:
                assert FLAGS.global_task == 'inference'
                if "nl2sva" in FLAGS.task:
                    if FLAGS.baseline_emsemble and FLAGS.voting_tech == 'LLM':
                        self.add_voting_agent(config_list)
                    if FLAGS.use_RAG and 'Suggestions' in FLAGS.RAG_content:
                        if FLAGS.Suggestions_Reasoning:
                            self.add_Suggestions_Reasoning_agent(config_list)


    def add_helper_agents(self, config_list):
        for i, helper in enumerate(FLAGS.helper_list):
            tools = []
            if FLAGS.agent_arch == "four_agents" and i == len(FLAGS.helper_list) - 1:
                tools = ['evaluate_jg']

            self.agent_configs.append(
                {
                    'type': 'AssistantAgent',
                    'tools': tools,
                    'transform_message': {
                        'method': [],
                        'args': [{'llm_config': {"config_list": config_list, "cache_seed": None}, 'max_token': FLAGS.max_token}], # Lily: max_token = 800 originally
                    },
                    'base_agent_config': {
                        'name': f'Helper{i+1}',
                        'description': 'Assistant who provides suggestions self-learned previously and comment them in the next talk.',
                        'is_termination_msg': lambda x: x.get("content", "")
                        and x.get("content", "").rstrip().endswith("TERMINATE"),
                        'system_message': helper,
                        'llm_config': {
                            "config_list": config_list,
                            "cache_seed": None,
                            "temperature": 0.1,
                            "top_p": 1,
                        },
                    },
                }
            )

    def add_jaspergold_agent(self, config_list, evaluate_jg):
        self.agent_configs.append(
            {
                'type': 'UserProxyAgent',
                'tools': ['evaluate_jg'],
                'base_agent_config': {
                    'name': 'JasperGold',
                    'human_input_mode': "TERMINATE",
                    'is_termination_msg': lambda x: x.get("content", "")
                    and x.get("content", "").rstrip().endswith("TERMINATE"),
                    'max_consecutive_auto_reply': 2,
                    'code_execution_config': False,
                    'llm_config': {
                        "config_list": config_list,
                        "cache_seed": None,
                        "temperature": FLAGS.temperature,
                        "top_p": 1,
                    },
                },
            }
        )
        self.tool_configs.append(
            {
                'function_call': evaluate_jg,
                'executor': "Helper1",
                'caller': "JasperGold",
                'name': "evaluate_jg",
                'description': '\tUse this tool to evaluate JasperGold results for given LLM_response with optional RTL design inclusion.',
                'tool_examples': '',
            }
        )

    def add_RAG_reflection_agent(self, config_list):
        # if 'Examples' in FLAGS.RAG_content: # This could be directly saved as the list
        if FLAGS.global_task == 'train':
            self.agent_configs.append(
                {
                    'type': 'AssistantAgent',
                    'tools': [],
                    'transform_message': {
                        'method': [],
                        'args': [{'llm_config': {"config_list": config_list, "cache_seed": None}, 'max_token': FLAGS.max_token}],
                    },
                    'base_agent_config': {
                        'name': 'Reflection',
                        'description': 'Assistant who reflects on the differences between LLM-generated and reference assertions, providing concise, one-sentence suggestions for future assertion generations without mentioning specific signal names.',
                        'is_termination_msg': lambda x: x.get("content", "")
                        and x.get("content", "").rstrip().endswith("TERMINATE"),
                        'system_message': 'You are an SystemVerilog Assertion assistant who reflects on the differences between generated and reference assertions, providing improvement suggestions without mentioning specific signals.',
                        'llm_config': {
                            "config_list": config_list,
                            "cache_seed": None,
                            "temperature": FLAGS.temperature,
                            "top_p": 1,
                        },
                    },
                },
            # }
            )

    def add_voting_agent(self, config_list):
        self.agent_configs.append(
            {
                'type': 'AssistantAgent',
                'tools': [],
                'transform_message': {
                    'method': [],
                    'args': [
                        {'llm_config': {"config_list": config_list, "cache_seed": None}, 'max_token': 1000}
                    ],
                },
                'base_agent_config': {
                    'name': 'voting',
                    'description': 'Assistant who evaluates LLM-generated SystemVerilog Assertions (SVA) and chooses the most optimal solution based on natural language descriptions, providing numeric ratings and constructive feedback.',
                    'is_termination_msg': lambda x: x.get("content", "")
                    and x.get("content", "").rstrip().endswith("TERMINATE"),
                    'system_message': '''You are an expert SystemVerilog Assertion (SVA) evaluator. Your task is to assess multiple LLM-generated SVAs based on given natural language descriptions and determine which solution is the best. For each evaluation:

1. Evaluate each candidate solution individually based on the following rubric:
- Correctness: Does the SVA accurately capture the intended behavior?
- Completeness: Does the SVA cover all aspects mentioned in the description?
- Syntax: Is the SVA syntactically correct?
- Efficiency: Is the assertion written in an optimal and clear manner?
- Edge cases: Does the SVA account for potential edge cases?

2. Compare the candidate solutions and use the above criteria to decide which solution is the best.

3. Provide your evaluation in the following format:
Enclose your SVA code with ```systemverilog and ```. Only output the best code snippet and do NOT output anything else.

Answer:
```systemverilog
assert property(@(posedge clk)
(sig_A && !sig_B) |-> sig_C
);
```
"""

''',
                    'llm_config': {
                        "config_list": config_list,
                        "cache_seed": None,
                        "temperature": FLAGS.temperature,
                        "top_p": 1,
                    },
                },
            }
        )

    def add_Suggestions_Reasoning_agent(self, config_list):
        self.agent_configs.append(
            {
                'type': 'AssistantAgent',
                'tools': [],
                'transform_message': {
                    'method': [],
                    'args': [{'llm_config': {"config_list": config_list, "cache_seed": None}, 'max_token': FLAGS.max_token}], 
                },
                'base_agent_config': {
                    'name': 'Suggestions_Reasoning',
                    'description': 'Assistant that selects relevant suggestions to improve SystemVerilog Assertion generation based on provided context.',
                    'is_termination_msg': lambda x: x.get("content", "")
                    and x.get("content", "").rstrip().endswith("TERMINATE"),
                    'system_message': '''You are a SystemVerilog Assertion expert. 
                    You will receive:
                    1. Natural language descriptions
                    2. Design module details (if available)
                    3. Testbench information (if available)
                    4. A list of suggestion candidates

                    Your tasks are:
                    1. Analyze the provided information and suggestions
                    2. Select the most relevant suggestions to improve the clarity and robustness of assertions
                    3. Append these selected suggestions to your response

                    Focus on suggestions that directly enhance the assertions, even if they are more cautious.''',
                    'llm_config': {
                        "config_list": config_list,
                        "cache_seed": None,
                        "temperature": FLAGS.temperature,
                        "top_p": 1,
                    },
                },
            }
        )
    
    def add_prune_agent(self, config_list):
        self.agent_configs.append(
            {
                'type': 'AssistantAgent',
                'tools': [],
                'transform_message': {
                    'method': ['LLMSummary'],
                    'args': [{'llm_config': {"config_list": config_list, "cache_seed": None}, 'max_token': FLAGS.max_token}],
                },
                'base_agent_config': {
                    'name': 'Prune_Assertions',
                    'description': 'Assistant for refining SystemVerilog Assertions (SVAs) by filtering out repetitive or unqualified assertions and retaining the most varied and relevant ones.',
                    'is_termination_msg': lambda x: x.get("content", "")
                    and x.get("content", "").rstrip().endswith("TERMINATE"),
                    'system_message': "Review and prune the provided SVAs, removing redundant or unqualified ones. Keep only the most varied and relevant assertions, focusing on signal interactions and design features to ensure comprehensive verification coverage.",
                    'llm_config': {"config_list": config_list, "[cache]_seed": None, "temperature": FLAGS.temperature, "top_p": 1},
                },
            }
        )
    
    def add_design_meta_agent(self, config_list):
        self.agent_configs.append(
            {
                'type': 'AssistantAgent',
                'tools': [],
                'transform_message': {
                    'method': ['LLMSummary'],
                    'args': [{'llm_config': {"config_list": config_list, "cache_seed": None}, 'max_token': FLAGS.max_token}],
                },
                'base_agent_config': {
                    'name': 'Design_Meta_Specification',
                    'description': 'Agent responsible for generating line-wise and block-wise specifications based on the design RTL, focusing on critical interactions and structure for verification purposes.',
                    'is_termination_msg': lambda x: x.get("content", "")
                    and x.get("content", "").rstrip().endswith("TERMINATE"),
                    'system_message': "Generate detailed line-wise and block-wise specifications based on the design RTL. Focus on capturing key interactions, modules, and structural elements to support thorough verification.",
                    'llm_config': {"config_list": config_list, "[cache]_seed": None, "temperature": FLAGS.temperature, "top_p": 1},
                },
            }
        )

    def add_ICRL_reasoning_agent(self, config_list):
        self.agent_configs.append(
            {
                'type': 'AssistantAgent',
                'tools': [],
                'transform_message': {
                    'method': ['LLMSummary'],
                    'args': [{'llm_config': {"config_list": config_list, "cache_seed": None}, 'max_token': FLAGS.max_token}],
                },
                'base_agent_config': {
                    'name': 'ICRL_Reasoning',
                    'description': 'Agent for reasoning why each assertion could cover new verification holes, providing a paragraph of explanation per assertion.',
                    'is_termination_msg': lambda x: x.get("content", "")
                    and x.get("content", "").rstrip().endswith("TERMINATE"),
                    'system_message': "For each assertion, provide a paragraph explaining its coverage rationale and how it addresses any verification gaps, ensuring comprehensive understanding of each assertion’s purpose.",
                    'llm_config': {"config_list": config_list, "[cache]_seed": None, "temperature": FLAGS.temperature, "top_p": 1},
                },
            }
        )


    def main_fv(self):
        # tool configs

        self.tool_configs = []

        # The release path uses a single OpenAI-compatible model entry.
        config_list = [{"model": FLAGS.llm_model}]
        assert type(config_list) is list and len(config_list) == 1
        # LLM config list
        llm_model = FLAGS.llm_model

        config_list[0]['model'] = llm_model
        if FLAGS.llm_model in [
            "mistralai/mixtral-8x22b-instruct-v0.1",
            "mixtral_8x7b",
            "meta/llama3-70b-instruct",
            "meta/llama3-8b-instruct",
        ]:
            config_list[0]['api_key'] = FLAGS.api_key
            config_list[0].setdefault('base_url', FLAGS.base_url)
        print(config_list)

        os.makedirs("coding", exist_ok=True)

        TASK_TO_HEADER = {
            "nl2sva_machine": lambda: prompts_nl2sva_machine.SVAGEN_HEADER,
            "nl2sva_opencore": lambda: prompts_nl2sva_machine.SVAGEN_HEADER,
            "nl2sva_human": lambda: prompts_nl2sva_human.SVAGEN_HEADER,
        }

        # agent configs
        self.agent_configs = [
            {
                'type': 'UserProxyAgent',
                'tools': [],
                'base_agent_config': {
                    'name': 'user',
                    'description': 'User proxy who asks questions and executes the tools with the provided input from Assistant.',
                    'human_input_mode': "NEVER",
                    'is_termination_msg': lambda x: x.get("content", "")
                    and x.get("content", "").rstrip().endswith("TERMINATE"),
                    'max_consecutive_auto_reply': 0,
                    'code_execution_config': False,
                    # 'code_execution_config': {"executor": code_executor},
                },
            },
            {
                'type': 'AssistantAgent',
                'tools': [],
                'transform_message': {
                    'method': ['LLMSummary'],
                    'args': [{'llm_config': {"config_list": config_list, "cache_seed": None}, 'max_token': FLAGS.max_token}],  # Lily: max_token = 800 originally
                },
                'base_agent_config': {
                    'name': 'Coding',
                    'description': 'Assistant who reasons the problem and uses the provided tools to resolve the task.',
                    'is_termination_msg': lambda x: x.get("content", "")
                    and x.get("content", "").rstrip().endswith("TERMINATE"),
                    'system_message': TASK_TO_HEADER.get(FLAGS.task, lambda: None)(),
                    'llm_config': {"config_list": config_list, "[cache]_seed": None, "temperature": FLAGS.temperature, "top_p": 1},
                },
            },
        ]

        self.process_agents(config_list, evaluate_jg)

        # Prompt making
        tool_tbl = create_tool_tbl(self.tool_configs)

        for agent in self.agent_configs:
            tool_names, formatted_tools = get_tools_descriptions(agent['tools'], tool_tbl)
            # ReACT prompt
            formatted_format_instructions = FORMAT_INSTRUCTIONS.format(tool_names=tool_names)
            ReAct_prompt = "\n\n".join([PREFIX, formatted_tools, formatted_format_instructions, SUFFIX])

            # if agent['type'] == 'UserProxyAgent':
            #     Initial_prompt = ReAct_prompt
            # elif agent['type'] == 'AssistantAgent':
            #     agent['base_agent_config']['system_message'] = (
            #         "Only use the tools you have been provided with. \nHere are "
            #         "provided tools:\n" + formatted_tools
            #         #   + "\nReply TERMINATE when you have the Final Answer."
            #     )

        if FLAGS.LLM_gateaway in {"openai", "claude"}:
            self.lightweight_agents = self._build_lightweight_agents()

        if FLAGS.global_task == 'inference':
            self._run_benchmark(self.bmark_launcher, FLAGS.task)

        elif FLAGS.global_task == 'train':
            # print(f'self.train_launcher={self.train_launcher}')
            for task, launcher in self.train_launcher.items():
                self._run_benchmark(launcher, task)
            saver.dump_knolwedge_to_disk()

    def _run_benchmark(self, bmark_launcher, task):
        if task == "nl2sva_human":
            bmark_launcher.run_benchmark(temperature=FLAGS.temperature, max_tokens=FLAGS.max_token, num_cases=1) # max_tokens = 200 originally
        elif task == "nl2sva_machine":
            bmark_launcher.run_benchmark(temperature=FLAGS.temperature, max_tokens=FLAGS.max_token, num_cases=1) # max_tokens = 100 originally
        elif task == "nl2sva_opencore":
            bmark_launcher.run_benchmark(temperature=FLAGS.temperature, max_tokens=FLAGS.max_token, num_cases=1) # max_tokens = 100 originally
        else:
            print(f"Unsupported eval mode")
            raise NotImplementedError

    def call_agent_get_response(self, system_prompt, user_prompt, row):

        # # Construct the FV
        FV_prompt = user_prompt
        # print(f"@@@@FV Prompt: {FV_prompt}")

        if FLAGS.LLM_gateaway in {"openai", "claude"}:
            agents = getattr(self, "lightweight_agents", None) or self._build_lightweight_agents()
            self.lightweight_agents = agents
            lm_response = self._run_lightweight_nl2sva(agents, system_prompt, FV_prompt, row)

            if FLAGS.global_task == "train" and not FLAGS.use_JG:
                from self_learning import self_learn

                self_learn(agents, lm_response, FV_prompt, row)

            return lm_response

        from hardware_general_agent import HardwareAgent

        # Add system prompt
        self.agent_configs[0]['base_agent_config']['system_message'] = system_prompt
        fv_agent = HardwareAgent(
            agent_configs=self.agent_configs,
            tool_configs=self.tool_configs,
            example_rag_agent=self.example_rag_agent,
            suggestion_rag_agent=self.suggestion_rag_agent,
        )

        if FLAGS.LLM_gateaway not in {"openai", "claude"}:
            fv_agent.revalidate_llm_config()

        return fv_agent.initiate_chat(message=FV_prompt, row=row)

if __name__ == "__main__":
    processor = FVProcessor()
    processor.main_fv()