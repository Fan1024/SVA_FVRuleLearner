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
import glob
import re
import shutil
import multiprocessing
import time
from dataclasses import asdict
from typing import Optional, Dict

import pandas as pd
from tqdm import tqdm
import evaluate

# Get the directory of the current file
current_file_directory = os.path.dirname(os.path.abspath(__file__))

from saver import saver
from config import FLAGS

print = saver.log_info

from FVEval.fv_eval import utils, fv_tool_execution
from FVEval.fv_eval.data import LMResult, TextSimilarityEvaluationResult, JGEvaluationResult
# Not sure whether I need to add 'FVEval.'

"""
Base Evaluator Class for Executing FVEval Evaluation Flow
"""


class Evaluator(object):
    def __init__(
        self,
        task: str,
        llm_output_dir: str,
        model_name: str,
        temp_dir: str,
        save_dir: str,
        parallel_jobs: int = 8,
        cleanup_temp_files: bool = True,
        debug: bool = False,
    ):
        self.task = task
        self.llm_output_dir = llm_output_dir
        self.temp_dir = temp_dir
        self.save_dir = save_dir
        self.parallel_jobs = parallel_jobs
        self.cleanup_temp_files = cleanup_temp_files
        self.debug = debug

        # load all results and store them in a list of FVEvalLMResponse
        # DEBUG: Lily0923: remove the condition on global_task
        if FLAGS.global_task != 'train':
            if model_name:
                llm_results = glob.glob(f"{llm_output_dir}/*{model_name}_*.csv")
            else:
                # if empty model name, load all results in the directory
                llm_results = glob.glob(f"{llm_output_dir}/*.csv")
            assert (
                len(llm_results) > 0
            ), f"No LLM results found in {llm_results}; model_name={model_name}; llm_output_dir={llm_output_dir}"
            llm_results = [
                (f.split("/")[-1].split(".csv")[0], pd.read_csv(f)) for f in llm_results
            ]
            self.llm_results = [
                (exp_id, [LMResult(**r) for _, r in df.iterrows()])
                for exp_id, df in llm_results
            ]

        # setup temp and save directories
        if not os.path.isdir(temp_dir):
            utils.mkdir_p(temp_dir)
        if not os.path.isdir(save_dir):
            utils.mkdir_p(save_dir)

        # set tcl file path
        self.tcl_file_path = self.set_tcl_file_path()

        # load similarity metrics
        self.similarity_metrics = {
            "bleu": evaluate.load("bleu"),
            "rouge": evaluate.load("rouge"),
            "exact_match": evaluate.load("exact_match"),
        }

    def set_tcl_file_path(
        self,
    ):
        if "nl2sva" in self.task:
            tcl_file_path = FLAGS.tcl_eval_file_path# TODO: see whether we need to change the tcl file
        # # tcl_file_path = os.path.join(current_file_directory, '..', tcl_file_path)

        # tcl_file_path = os.path.abspath(
        #     os.path.join(os.path.dirname(current_file_directory), tcl_file_path)
        # )

        # if tcl_file_path is not None and not os.path.isfile(tcl_file_path):
        #     utils.print_error(f"TCL file not found", tcl_file_path)
        #     raise FileNotFoundError
        # if self.debug:
        #     print(f"Set TCL file path to {tcl_file_path}")
        # return tcl_file_path
        if self.debug:
            print(f"Set TCL file path to {tcl_file_path}")
        return tcl_file_path

    def write_design_sv(
        self,
        results_list: list[LMResult],
    ):
        # For each result, write the packaged testbench to a SystemVerilog file
        # in the subdir directory
        for r in results_list:
            with open(f"{self.temp_dir}/{r.experiment_id}_{r.task_id}.sv", "w") as f:
                f.write(r.design_rtl)

    def write_testbench_sv(
        self,
        results_list: list[LMResult],
    ):
        # For each result, write the packaged testbench to a SystemVerilog file
        # in the subdir directory
        for r in results_list:
            tb = r.output_tb
            with open(f"{self.temp_dir}/{r.experiment_id}_{r.task_id}.sva", "w") as f:
                f.write(tb) 
    
    def write_sva(
        self,
        results_list: list[LMResult],
    ):
        # For each result, write the packaged testbench to a SystemVerilog file
        # in the subdir directory
        for r in results_list:
            sva = utils.parse_code_response(r.response)
            with open(f"{self.temp_dir}/{r.experiment_id}_{r.task_id}.sva", "w") as f:
                f.write(sva) 

    def setup_jg_evaluation(
        self,
        result_list: list[LMResult],
    ):
        # For each result, write the packaged testbench to a SystemVerilog file
        # in the temp directory
        for r in result_list:
            with open(f"{self.temp_dir}/{r.experiment_id}_{r.task_id}.sv", "w") as f:
                f.write(r.design_rtl)
            with open(f"{self.temp_dir}/{r.experiment_id}_{r.task_id}.sva", "w") as f:
                f.write(r.output_tb)

    def calculate_jg_metric(
        self,
        jasper_out_str: str,
    ):
        raise NotImplementedError

    def calculate_similiarty_metric(
        self,
        lm_response: str,
        ref_solution: str,
        original_setting: bool = True,
    ):
        metric_values = {}

        # Handle cases where lm_response or ref_solution are not strings
        if pd.isna(lm_response) or pd.isna(ref_solution):
            utils.print_error(f"Invalid lm_response or ref_solution")
            return {"bleu": 0.0, "rouge": 0.0, "exact_match": 0.0}

        if not original_setting:
            lm_response = utils.parse_code_response(lm_response)
        for metric_name, metric_func in self.similarity_metrics.items():
            metric_output = metric_func.compute(
                predictions=[lm_response], references=[ref_solution]
            )
            if metric_name == "bleu":
                metric_values[metric_name] = metric_output["bleu"]
            elif metric_name == "rouge":
                metric_values[metric_name] = metric_output["rougeL"]
            elif metric_name == "exact_match":
                metric_values[metric_name] = metric_output["exact_match"]
            else:
                utils.print_error(f"Similarity metric not supported", metric_name)
                raise NotImplementedError
        return metric_values

    def evaluate_text_similiarty(
        self,
        result_list: list[LMResult],
    ):
        eval_results = []
        for lm_result in result_list:
            # calculate similarity metric
            metric_values = self.calculate_similiarty_metric(
                lm_result.response,
                lm_result.ref_solution,
            )
            eval_results.append(
                TextSimilarityEvaluationResult(
                    experiment_id=lm_result.experiment_id,
                    task_id=lm_result.task_id,
                    model_name=lm_result.model_name,
                    **metric_values,
                )
            )
        return eval_results

    def evaluate_jg(
        self,
        result_list: list[LMResult],
        with_rtl_design: bool = False,
    ):
        # setup temp and save directories
        if not os.path.isdir(self.temp_dir):
            utils.mkdir_p(self.temp_dir)
        # For each result, write the packaged testbench to a SystemVerilog file
        # in the temp directory
        if with_rtl_design:
            self.write_design_sv(result_list)
        self.write_testbench_sv(result_list)

        # set up execution parameters
        model_name = result_list[0].model_name
        experiment_id = result_list[0].experiment_id
        num_test_cases = len(result_list)
        num_batchs = num_test_cases // self.parallel_jobs + 1
        eval_results = []

        # iterate over all test cases
        for batch_id in tqdm(
            range(num_batchs),
            desc=f"Evaluating test cases {model_name} {experiment_id}",
        ):
            jasper_outputs = []

            # launch parallel jobs
            processes = []
            output_queue = multiprocessing.Queue()

            # iterate over all parallel workers
            for worker_id in range(self.parallel_jobs):
                index = batch_id * self.parallel_jobs + worker_id
                if index >= num_test_cases:
                    continue

                lm_result = result_list[index]
                assert lm_result.model_name == model_name
                assert lm_result.experiment_id == experiment_id

                if self.parallel_jobs == 1:
                    jasper_out_str = fv_tool_execution.launch_jg(
                        tcl_file_path=self.tcl_file_path,
                        sv_dir=self.temp_dir,
                        experiment_id=lm_result.experiment_id,
                        task_id=lm_result.task_id,
                    )
                    jasper_outputs.append(jasper_out_str)
                    # if self.debug:
                        # print(f"@@@Jasper Outputs:{jasper_out_str}") #DEBUG
                else:
                    p = multiprocessing.Process(
                        target=fv_tool_execution.launch_jg_with_queue,
                        kwargs={
                            "tcl_file_path": self.tcl_file_path,
                            "sv_dir": self.temp_dir,
                            "experiment_id": lm_result.experiment_id,
                            "task_id": lm_result.task_id,
                            "output_queue": output_queue,
                        },
                    )
                    processes.append(p)
                    p.start()
            if self.parallel_jobs > 1:
                for p in processes:
                    p.join()
                while not output_queue.empty():
                    jasper_outputs.append(output_queue.get())

            for jasper_out_str in jasper_outputs:
                # regex match *.sva in jasper_out_str
                task_id_match = re.findall(r"\bTASK_ID[^\n]*", jasper_out_str)
                if not task_id_match:
                    raise ValueError(f"Jasper output does not contain unique id (UID)")
                task_id = task_id_match[0].split("TASK_ID ")[-1]

                # if self.debug: # Lily0916: remove this
                #     print(f"@@@JasperGold: {jasper_out_str}")
                result_dict = self.calculate_jg_metric(jasper_out_str)
                eval_results.append(
                    JGEvaluationResult(
                        experiment_id=experiment_id,
                        task_id=task_id,
                        model_name=model_name,
                        **result_dict,
                    )
                )
        if self.cleanup_temp_files:
            for i in range(3):
                try:
                    shutil.rmtree(self.temp_dir)
                    break
                except OSError as e:
                    if i < 2:
                        time.sleep(1)
                    else:
                        print(f"Warning: Failed to cleanup temp dir {self.temp_dir}: {e}")
        return eval_results

    def run_evaluation(
        self,
    ):
        for exp_name, result_list in self.llm_results:
            if ("similarity" in FLAGS.eval_content and FLAGS.global_task == 'eval') or (FLAGS.global_task == 'inference'):
                text_similiarty_eval_results = self.evaluate_text_similiarty(result_list)
                text_similiarty_eval_results = [
                    asdict(r) for r in text_similiarty_eval_results
                ]
                text_similiarty_eval_results = pd.DataFrame(text_similiarty_eval_results)
                text_similiarty_eval_results.to_csv(
                    f"{self.save_dir}/{exp_name}_sim.csv", index=False
                )
                results = text_similiarty_eval_results

            if ("jg" in FLAGS.eval_content and FLAGS.global_task == 'eval') or (FLAGS.global_task == 'inference'):
                jg_eval_results = self.evaluate_jg(result_list)
                jg_eval_results = [asdict(r) for r in jg_eval_results]
                jg_eval_results = pd.DataFrame(jg_eval_results)
                jg_eval_results.to_csv(f"{self.save_dir}/{exp_name}_jg.csv", index=False)
                results = jg_eval_results

            if ("similarity" in FLAGS.eval_content and "jg" in FLAGS.eval_content and FLAGS.global_task == 'eval') or (FLAGS.global_task == 'inference'):
                jg_eval_results["unique_task_id"] = jg_eval_results["task_id"].apply(
                    lambda x: x.split("_trial")[0]
                )
                # for rows that share same unique_task_id, only take the max value
                jg_eval_results = jg_eval_results.groupby("unique_task_id").max()

                # take only the metric values from the evaluation results
                combined_results = pd.merge(
                    text_similiarty_eval_results,
                    jg_eval_results,
                    on=["experiment_id", "task_id", "model_name"],
                )
                
                # Lily: JasperGold Bug Quick Fix
                # Update functionality to 1 if BLEU = 1.0
                # This implements the logic: functionality = 1 if (JasperGold = 1 OR BLEU = 1.0)
                combined_results.loc[combined_results['bleu'] == 1.0, 'functionality'] = 1.0
                combined_results.loc[combined_results['bleu'] == 1.0, 'func_relaxed'] = 1.0
                
                # drop the columns that are not metric values
                combined_results = combined_results.drop(
                    columns=["experiment_id", "task_id", "model_name"]
                )
                # for each remaining column, calculate the mean value
                # add as a separate row
                mean_values = combined_results.mean(axis=0)
                mean_values = mean_values.to_frame().T
                mean_values["experiment_id"] = exp_name
                mean_values["task_id"] = "mean"
                mean_values["model_name"] = "mean"
                combined_results = pd.concat(
                    [combined_results, mean_values], ignore_index=True
                )
                combined_results.to_csv(f"{self.save_dir}/{exp_name}.csv", index=False)
                results = combined_results
        return results

    def save_evaluation_results(
        self,
        eval_results: list[JGEvaluationResult],
    ):
        eval_results = [asdict(r) for r in eval_results]
        eval_results = pd.DataFrame(eval_results)
        eval_results.to_csv(f"{self.save_dir}/jg_eval_results.csv", index=False)
        return eval_results


"""
Evaluator for NL2SVA-HUman
Implements a custom:
    - 'evaluate_jg' method that invokes proprety-equivalence checks
    - 'calculate_jg_metric' method that analyzes and reports syntax and funcational correctness specific to NL2SVA-Human
"""


class NL2SVAHumanEvaluator(Evaluator):
    def __init__(
        self,
        llm_output_dir: str,
        model_name: str,
        temp_dir: str,
        save_dir: str,
        parallel_jobs: int = 8,
        cleanup_temp_files: bool = True,
        debug: bool = False,
    ):
        super().__init__(
            task="nl2sva_human",
            llm_output_dir=llm_output_dir,
            model_name=model_name,
            temp_dir=temp_dir,
            save_dir=save_dir,
            parallel_jobs=parallel_jobs,
            cleanup_temp_files=cleanup_temp_files,
            debug=debug,
        )

    def evaluate_jg(
        self,
        result_list: list[LMResult],
        with_rtl_design: bool = False,
        return_jg_info: bool = False  # New parameter
    ):
        # setup temp and save directories
        if not os.path.isdir(self.temp_dir):
            utils.mkdir_p(self.temp_dir)
        # For each result, write the packaged testbench to a SystemVerilog file
        # in the temp directory
        if with_rtl_design:
            self.write_design_sv(result_list)
        self.write_testbench_sv(result_list)

        # set up execution parameters
        model_name = result_list[0].model_name
        experiment_id = result_list[0].experiment_id
        num_test_cases = len(result_list)
        num_batchs = num_test_cases // self.parallel_jobs + 1
        eval_results = []

        # iterate over all test cases
        for batch_id in tqdm(
            range(num_batchs),
            desc=f"Evaluating test cases {model_name} {experiment_id}",
        ):
            jasper_outputs = []

            # launch parallel jobs
            processes = []
            output_queue = multiprocessing.Queue()

            # iterate over all parallel workers
            for worker_id in range(self.parallel_jobs):
                index = batch_id * self.parallel_jobs + worker_id
                if index >= num_test_cases:
                    continue

                lm_result = result_list[index]
                assert lm_result.model_name == model_name
                assert lm_result.experiment_id == experiment_id

                lm_assertion_text = (
                    utils.parse_code_response(lm_result.response)
                    .strip()
                    .replace("\n", "")
                )
                lm_assertion_text = (
                    lm_assertion_text.split("tb_reset)")[-1]
                    .strip()
                    .split(");")[0]
                    .strip()
                )

                ref_assertion_text = lm_result.ref_solution.strip().replace("\n", "")
                ref_assertion_text = (
                    ref_assertion_text.split("tb_reset)")[-1]
                    .strip()
                    .split(");")[0]
                    .strip()
                )

                signal_list = re.findall(r"'([^'\s]+)'", lm_result.user_prompt)

                params = re.findall(
                    r"\b(parameter|localparam)\s+(int\s+|real\s+|bit\s+|\[[^]]+\]\s*)?(\w+)",
                    lm_result.output_tb,
                )
                params = [m[2] for m in params]
                signal_list.extend(params)
                signal_list_text = ",".join(signal_list)

                if self.parallel_jobs == 1:
                    jasper_out_str = fv_tool_execution.launch_jg_custom_equiv_check(
                        tcl_file_path=self.tcl_file_path,
                        lm_assertion_text=lm_assertion_text,
                        ref_assertion_text=ref_assertion_text,
                        signal_list_text=signal_list_text,
                        sv_dir=self.temp_dir,
                        experiment_id=lm_result.experiment_id,
                        task_id=lm_result.task_id,
                    )
                    # 0914 DEBUG
                    # print(f"JasperGold Output[{lm_result.experiment_id}_{lm_result.task_id}]:{jasper_out_str}")
                    # breakpoint()

                    jasper_outputs.append(jasper_out_str)
                else:
                    p = multiprocessing.Process(
                        target=fv_tool_execution.launch_jg_with_queue_custom_equiv_check,
                        kwargs={
                            "tcl_file_path": self.tcl_file_path,
                            "lm_assertion_text": lm_assertion_text,
                            "ref_assertion_text": ref_assertion_text,
                            "signal_list_text": signal_list_text,
                            "sv_dir": self.temp_dir,
                            "experiment_id": lm_result.experiment_id,
                            "task_id": lm_result.task_id,
                            "output_queue": output_queue,
                        },
                    )
                    processes.append(p)
                    p.start()
            if self.parallel_jobs > 1:
                for p in processes:
                    p.join()
                while not output_queue.empty():
                    jasper_outputs.append(output_queue.get())

            for jasper_out_str in jasper_outputs:
                # regex match *.sva in jasper_out_str
                task_id_match = re.findall(r"\bTASK_ID[^\n]*", jasper_out_str)
                if not task_id_match:
                    raise ValueError(f"Jasper output does not contain unique id (UID)")
                task_id = task_id_match[0].split("TASK_ID ")[-1]

                # if self.debug:
                #     print(f"@@@JasperGold: {jasper_out_str}")
                # print(f"@@@JasperGold: {jasper_out_str}")
                # breakpoint()

                if self.task == "nl2sva_opencore":
                    result_dict = self.calculate_jg_metric_opencore(jasper_out_str)
                else:
                    result_dict = self.calculate_jg_metric(jasper_out_str)
                eval_results.append(
                    JGEvaluationResult(
                        experiment_id=experiment_id,
                        task_id=task_id,
                        model_name=model_name,
                        **result_dict,
                    )
                )
        if self.cleanup_temp_files:
            for i in range(3):
                try:
                    shutil.rmtree(self.temp_dir)
                    break
                except OSError as e:
                    if i < 2:
                        time.sleep(1)
                    else:
                        print(f"Warning: Failed to cleanup temp dir {self.temp_dir}: {e}")
            
        if return_jg_info:
            return eval_results, jasper_outputs
        else:
            return eval_results

    def calculate_jg_metric(
        self,
        jasper_out_str: str,
    ):
        # check for syntax error
        syntax_error_match = re.findall(r"syntax error", jasper_out_str)
        if syntax_error_match:
            return {
                "syntax": 0.0,
                "functionality": 0.0,
                "func_relaxed": 0.0,
                # "bound_improve": 0.0,
            }

        # check for functionality error
        # match for "Full equivalence" in jaspert output string
        full_equiv_match = re.findall(r"Full equivalence", jasper_out_str)
        partial_equiv_match = re.findall(r"implies", jasper_out_str)
        if not full_equiv_match:
            if not partial_equiv_match:
                return {
                    "syntax": 1.0,
                    "functionality": 0.0,
                    "func_relaxed": 0.0,
                    # "bound_improve": 0.0,
                }
            else:
                return {
                    "syntax": 1.0,
                    "functionality": 0.0,
                    "func_relaxed": 1.0,
                }
        return {
            "syntax": 1.0,
            "functionality": 1.0,
            "func_relaxed": 1.0,
        }


"""
Evaluator for NL2SVA-Machine
Implements a custom:
    - 'evaluate_jg' method that invokes proprety-equivalence checks
    - 'calculate_jg_metric' method that analyzes and reports syntax and funcational correctness specific to NL2SVA-Machine
"""


class NL2SVAMachineEvaluator(Evaluator):
    def __init__(
        self,
        task,
        llm_output_dir: str,
        model_name: str,
        temp_dir: str,
        save_dir: str,
        parallel_jobs: int = 8,
        cleanup_temp_files: bool = True,
        debug: bool = False,
    ):
        super().__init__(
            task=task,
            llm_output_dir=llm_output_dir,
            model_name=model_name,
            temp_dir=temp_dir,
            save_dir=save_dir,
            parallel_jobs=parallel_jobs,
            cleanup_temp_files=cleanup_temp_files,
            debug=debug,
        )

    def evaluate_jg(
        self,
        result_list: list[LMResult],
        with_rtl_design: bool = False,
    ):
        # setup temp and save directories
        if not os.path.isdir(self.temp_dir):
            utils.mkdir_p(self.temp_dir)
        # For each result, write the packaged testbench to a SystemVerilog file
        # in the temp directory
        if with_rtl_design:
            self.write_design_sv(result_list)
        if self.task == "nl2sva_machine":
            self.write_testbench_sv(result_list)

        # set up execution parameters
        model_name = result_list[0].model_name
        experiment_id = result_list[0].experiment_id
        num_test_cases = len(result_list)
        num_batchs = num_test_cases // self.parallel_jobs + 1
        eval_results = []

        # iterate over all test cases
        for batch_id in tqdm(
            range(num_batchs),
            desc=f"Evaluating test cases {model_name} {experiment_id}",
        ):
            jasper_outputs = []

            # launch parallel jobs
            processes = []
            output_queue = multiprocessing.Queue()

            # iterate over all parallel workers
            for worker_id in range(self.parallel_jobs):
                index = batch_id * self.parallel_jobs + worker_id
                if index >= num_test_cases:
                    continue
                lm_result = result_list[index]
                assert lm_result.model_name == model_name
                # assert lm_result.experiment_id == experiment_id

                if self.task == "nl2sva_machine":
                    lm_assertion_text = (
                        utils.parse_code_response(lm_result.response)
                        .strip()
                        .replace("\n", "")
                    )
                    lm_assertion_text = (
                        lm_assertion_text.split("clk)")[-1].strip().split(");")[0].strip()
                    )

                    ref_assertion_text = lm_result.ref_solution.strip().replace("\n", "")
                    ref_assertion_text = (
                        ref_assertion_text.split("clk)")[-1].strip().split(");")[0].strip()
                    )

                    signal_list = re.findall(r"\bsig_\w+", lm_result.ref_solution)
                    signal_list = list(set(signal_list))
                    signal_list_text = ",".join(signal_list)
                elif self.task == "nl2sva_opencore":
                    lm_assertion_text = (
                        utils.parse_code_response(lm_result.response)
                        .strip()
                        .replace("\n", "")
                    )
                    lm_assertion_text = utils.extract_assertion_formula(lm_assertion_text)
                    ref_assertion_text = lm_result.ref_solution.strip().replace("\n", "")
                    ref_assertion_text = utils.extract_assertion_formula(ref_assertion_text)

                    # print(f"@@@DEBUG: lm_assertion_text = {lm_assertion_text}")
                    # print(f"@@@DEBUG: ref_assertion_text = {ref_assertion_text}")
                    
                    # Extract signal names from the user prompt
                    if FLAGS.llm_model == "gpt-4":
                        signal_list = re.findall(r"'([a-zA-Z_]\w*)'", lm_result.user_prompt)
                    else:
                        # Fixed: Use proper escaping for quotes and backticks
                        signal_list = re.findall(r"['\"`]([a-zA-Z_]\w*)['\"`]", lm_result.user_prompt)
                    # Extract parameters
                    params = re.findall(
                        r"\b(parameter|localparam)\s+(int\s+|real\s+|bit\s+|\[[^]]+\]\s*)?(\w+)",
                        lm_result.output_tb,
                    )
                    params = [m[2] for m in params]
                    # Extend signal list with parameters
                    signal_list.extend(params)
                    # Filter out any invalid signal names
                    valid_signal_list = [sig for sig in signal_list if re.match(r"^[a-zA-Z_]\w*$", sig)]
                    # Deduplicate signal names
                    valid_signal_list = list(set(valid_signal_list))
                    # Join the signal names into a comma-separated string
                    signal_list_text = ",".join(valid_signal_list)

                # print(f"@@@DEBUG: signal_list_text = {signal_list_text}")
                # print(f"@@@DEBUG: lm_assertion_text = {lm_assertion_text}")
                # print(f"@@@DEBUG: ref_assertion_text = {ref_assertion_text}")

                if self.parallel_jobs == 1:
                    jasper_out_str = fv_tool_execution.launch_jg_custom_equiv_check(
                        tcl_file_path=self.tcl_file_path,
                        lm_assertion_text=lm_assertion_text,
                        ref_assertion_text=ref_assertion_text,
                        signal_list_text=signal_list_text,
                        sv_dir=self.temp_dir,
                        experiment_id=lm_result.experiment_id,
                        task_id=lm_result.task_id,
                    )
                    jasper_outputs.append(jasper_out_str)

                else:
                    p = multiprocessing.Process(
                        target=fv_tool_execution.launch_jg_with_queue_custom_equiv_check,
                        kwargs={
                            "tcl_file_path": self.tcl_file_path,
                            "lm_assertion_text": lm_assertion_text,
                            "ref_assertion_text": ref_assertion_text,
                            "signal_list_text": signal_list_text,
                            "sv_dir": self.temp_dir,
                            "experiment_id": lm_result.experiment_id,
                            "task_id": lm_result.task_id,
                            "output_queue": output_queue,
                        },
                    )
                    processes.append(p)
                    p.start()
            if self.parallel_jobs > 1:
                for p in processes:
                    p.join()
                while not output_queue.empty():
                    jasper_outputs.append(output_queue.get())
            for jasper_out_str in jasper_outputs:
                # regex match *.sva in jasper_out_str
                task_id_match = re.findall(r"\bTASK_ID[^\n]*", jasper_out_str)
                if not task_id_match:
                    raise ValueError(f"Jasper output does not contain unique id (UID)")
                task_id = task_id_match[0].split("TASK_ID ")[-1]

                # if self.debug:
                #     print(f"@@@JasperGold: {jasper_out_str}")
                # print(f"@@@JasperGold: {jasper_out_str}")
                # breakpoint()

                if self.task == "nl2sva_opencore":
                    result_dict = self.calculate_jg_metric_opencore(jasper_out_str)
                else:
                    result_dict = self.calculate_jg_metric(jasper_out_str)
                eval_results.append(
                    JGEvaluationResult(
                        experiment_id=experiment_id,
                        task_id=task_id,
                        model_name=model_name,
                        **result_dict,
                    )
                )
        if self.cleanup_temp_files:
            for i in range(3):
                try:
                    shutil.rmtree(self.temp_dir)
                    break
                except OSError as e:
                    if i < 2:
                        time.sleep(1)
                    else:
                        print(f"Warning: Failed to cleanup temp dir {self.temp_dir}: {e}")
        return eval_results

    def calculate_jg_metric(
        self,
        jasper_out_str: str,
    ):
        # check for syntax error
        syntax_error_match = re.findall(r"syntax error", jasper_out_str)
        if syntax_error_match:
            return {
                "syntax": 0.0,
                "functionality": 0.0,
                "func_relaxed": 0.0,
            }

        # check for functionality error
        # match for "Full equivalence" in jaspert output string
        full_equiv_match = re.findall(r"Full equivalence", jasper_out_str)
        partial_equiv_match = re.findall(r"implies", jasper_out_str)
        if not full_equiv_match:
            if not partial_equiv_match:
                return {
                    "syntax": 1.0,
                    "functionality": 0.0,
                    "func_relaxed": 0.0,
                    # "bound_improve": 0.0,
                }
            else:
                return {
                    "syntax": 1.0,
                    "functionality": 0.0,
                    "func_relaxed": 1.0,
                }
        return {
            "syntax": 1.0,
            "functionality": 1.0,
            "func_relaxed": 1.0,
        }

    def calculate_jg_metric_opencore(
        self,
        jasper_out_str: str,
    ):
        # check for syntax error
        syntax_error_match = re.findall(r"syntax error", jasper_out_str)
        
        # 1126
        # check for assumption conflict errors (EAS001, ERS055)
        # assumption_conflict = re.search(r"ERROR \((EAS001|ERS055)\)", jasper_out_str)
        
        if syntax_error_match: # or assumption_conflict:
            return {
                "syntax": 0.0,
                "functionality": 0.0,
                "func_relaxed": 0.0,
            }

        # check for functionality error
        # match for "Full equivalence" in jaspert output string
        full_equiv_count = jasper_out_str.count("Full equivalence")
        partial_equiv_match = re.findall(r"implies", jasper_out_str)

        if full_equiv_count < 2:
            if not partial_equiv_match:
                return {
                    "syntax": 1.0,
                    "functionality": 0.0,
                    "func_relaxed": 0.0,
                    # "bound_improve": 0.0,
                }
            else:
                return {
                    "syntax": 1.0,
                    "functionality": 0.0,
                    "func_relaxed": 1.0,
                }
        
        return {
            "syntax": 1.0,
            "functionality": 1.0,
            "func_relaxed": 1.0,
        }