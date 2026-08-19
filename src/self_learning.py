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
from saver import saver
import os
from typing import Any, Dict
from utils_agent import initiate_chat_with_retry, is_o_series_model

import re
from FVEval.fv_eval import utils as utils2
from FVEval.fv_eval.evaluation import NL2SVAHumanEvaluator, NL2SVAMachineEvaluator, LMResult
from saver import saver
import evaluate

print = saver.log_info

from config import FLAGS
from pprint import pformat
import fv_tools
import pickle
# from random import random
import time
import random
import tiktoken  # Make sure to install tiktoken with pip install tiktoken
from collections import OrderedDict
import json

# Import Q-Tree components from separate module
from qtree_builder import QTreeBuilder, QuestionNode, QuestionLevel

# Add these variables to keep track of the total time
total_gpt_time = 0
total_jaspergold_time = 0

def count_tokens(text):
    encoding = tiktoken.encoding_for_model("gpt-3.5-turbo")
    return len(encoding.encode(text))

def truncate_suggestions(suggestions, token_limit, prompt_length):
    truncated_suggestions = []
    total_length = prompt_length
    for suggestion in suggestions.split('\n'):
        suggestion_length = count_tokens(suggestion)
        if total_length + suggestion_length < token_limit:
            truncated_suggestions.append(suggestion)
            total_length += suggestion_length
        else:
            break
    return '\n'.join(truncated_suggestions)

def sort_suggestions(suggestion_dict):
    """
    Sorts the suggestions based on the given criteria.
    
    Parameters:
    suggestion_dict (OrderedDict): The dictionary containing suggestion sets and their metrics.
    only_BLEU (bool): A flag indicating if only BLEU metric should be considered.
    
    Returns:
    list: A list of sorted suggestion sets.
    """
    sorted_suggestions = []

    if FLAGS.only_BLEU:
        # Sort by BLEU score
        # print(f"@@@DEBUG: sorted_suggestions = {sorted_suggestions}")
        sorted_suggestions = sorted(suggestion_dict.items(), key=lambda item: item[1]['BLEU'], reverse=True)
    else:
        # Sort by functionality 0->1 first, relaxed functionality 0->1 second, BLEU score third
        sorted_suggestions = sorted(
            suggestion_dict.items(),
            key=lambda item: (
                item[1]['functionality'] == 0,  # Functionality 0->1
                item[1]['relaxed_functionality'] == 0,  # Relaxed functionality 0->1
                -item[1]['BLEU']  # Higher BLEU score
            )
        )

    return sorted_suggestions

def self_learn(agents, response, message, row):
    """
    Performs self-learning iterations to improve SVA generation based on PEC and BLEU metrics.
    
    Parameters:
    agents (dict): A dictionary containing the user and reflection agents.
    response (str): The initial response from the LLM-generated assertions.
    row (object): An object containing the natural language prompt, testbench, and reference solutions.
    
    Returns:
    None
    """
    global total_gpt_time, total_jaspergold_time  # Use global variables to keep track of the times

    iter_cnt = 0
    initial_pec = 0
    initial_relaxed_pec = 0
    fixable_indicator = 0
    initial_bleu = 0
    final_bleu = 0
    last_bleu = 0
    initial_metrics = None  # Will be set after first evaluation
    unfixable_indicator = 1
    partly_fixable_indicator = 0

    print('in self learning@@@@@')

    if FLAGS.task == "nl2sva_opencore":
        row.ref_solution = f"assert property({row.ref_solution});"
    response_str = response
    metrics = evaluate_pec_etc(response_str, row, only_bleu=False, last_bleu=last_bleu)
    reflection_response = ""
    suggestion_dict = OrderedDict()
    
    # Initialize lists to store metrics for each iteration
    bleu_scores = []
    functionality_scores = []
    relaxed_functionality_scores = []
    syntax_scores = []  # You'll need to implement a function to evaluate syntax

    pec, relaxed_pec, bleu, syntax = metrics['pec'], metrics['relax_pec'], metrics['bleu'], metrics['syntax']

    print(f'###Record: \n###Assertions: {response_str}')
    print(f'###Record: \n###pec: {pec}\n###relaxed_pec: {relaxed_pec}\n###bleu: {bleu}\n###syntax: {syntax}')

    bleu_scores.append(bleu)
    functionality_scores.append(pec)
    relaxed_functionality_scores.append(relaxed_pec)
    syntax_scores.append(syntax)

    # Store first metrics as previous_metrics for first iteration
    previous_metrics = {
        'pec': pec,
        'relax_pec': relaxed_pec,
        'bleu': bleu,
        'syntax': syntax
    }

    while iter_cnt < FLAGS.num_iter:
        print(f"###response: {response_str}")
        print(f"###reference solution: {row.ref_solution}")
        print(f"###pec: {metrics['pec']}")
        print(f"###relaxed pec: {metrics['relax_pec']}")
        print(f"###BLEU: {metrics['bleu']}")

        if iter_cnt == 0:
            initial_pec = pec
            initial_bleu = bleu
            initial_relaxed_pec = relaxed_pec
            # Store initial metrics for Q-tree saving
            # initial_metrics = {
            #     'pec': pec,
            #     'relax_pec': relaxed_pec,
            #     'bleu': bleu,
            #     'syntax': metrics.get('syntax', 0)
            # }

        # if iter_cnt == 0 and (abs(pec - 1.0) < 1e-6 or abs(bleu - 1.0) < 1e-6):
        if (abs(pec - 1.0) < 1e-6 or abs(bleu - 1.0) < 1e-6):
            final_bleu = bleu
            break

        temperature = adjust_temperature(iter_cnt, bleu, last_bleu)
        
        # Note: In newer versions of autogen, llm_config might not be directly accessible
        # as an attribute. We'll skip updating the temperature for now.
        # TODO: Find the correct way to update temperature in the current autogen version
        if not is_o_series_model(FLAGS.llm_model):
            # Check if Reflection agent exists and has llm_config attribute
            if "Reflection" in agents:
                if hasattr(agents["Reflection"], "llm_config"):
                    agents["Reflection"].llm_config["temperature"] = temperature
                else:
                    # Try accessing internal attributes
                    if hasattr(agents["Reflection"], "_llm_config"):
                        agents["Reflection"]._llm_config["temperature"] = temperature
                    else:
                        if FLAGS.debug:
                            print(f"Warning: Cannot update temperature for Reflection agent. Agent type: {type(agents['Reflection'])}")
            else:
                if FLAGS.debug:
                    print(f"Warning: Reflection agent not found in agents dictionary. Available agents: {list(agents.keys())}")

        if FLAGS.debug:
            print(f"@@@temperature: {temperature}")
            if "Reflection" in agents and hasattr(agents["Reflection"], "llm_config"):
                print(f'@@@agents["Reflection"].llm_config: {agents["Reflection"].llm_config}')

        if suggestion_dict:
            sorted_suggestions = sort_suggestions(suggestion_dict)
        else:
            sorted_suggestions = None

        # BRANCH HERE: Choose between Q-Tree and traditional reflection
        use_qtree = getattr(FLAGS, 'use_QTree', False)
        
        # Initialize variables that will be used later for knowledge extraction
        rules = []
        tree_nodes = []
        qtree_builder = None  # Initialize to None, will be set if use_qtree is True
        
        if use_qtree:
            # Q-Tree approach
            print("\n=== Using Q-Tree for reflection ===")
            qtree_builder = QTreeBuilder(agents)
            
            start_qtree = time.time()
            # Build Q-Tree for current assertion pair
            tree_nodes = qtree_builder.build_qtree_for_assertion_pair(
                generated_assertion=response_str,
                reference_assertion=row.ref_solution,
                row=row,
                metrics=metrics
            )
            total_qtree_time = time.time() - start_qtree
            # 1203: Lily Debugging
            print(f"@@@QTree QA Time: {qtree_builder.qa_time:.2f}s")
            print(f"@@@Total QTree Time: {total_qtree_time:.2f}s")
            if total_qtree_time > 0:
                 print(f"@@@QA Ratio: {qtree_builder.qa_time / total_qtree_time:.2%}")
            # Get aggregated rules from Q-Tree
            rules = qtree_builder.get_aggregated_rules()
            
            print(f"\n### Q-Tree generated {len(rules)} rules:")
            for rule in rules[:5]:  # Show first 5 rules
                print(f"  {rule}")
            
            # Q-Tree structure will be saved later if needed
            
            # Convert rules to reflection response format
            reflection_response = "\n".join(rules)
            
        else:
            # Traditional reflection approach
            reflection_response = prompt_self_reflection(
                agents["user"], agents["Reflection"], row, response_str, sorted_suggestions=sorted_suggestions
            )

        if FLAGS.debug:
            print(f"@@@@reflection_response(DEBUG): {reflection_response}")

        # Save the current suggestions and metrics
        if FLAGS.only_BLEU:
            suggestion_dict[iter_cnt] = {
                'suggestions': reflection_response,
                'BLEU': bleu
            }
        else:
            suggestion_dict[iter_cnt] = {
                'suggestions': reflection_response,
                'BLEU': bleu,
                'functionality': pec,
                'relaxed_functionality': relaxed_pec
            }

        # print(f"@@@DEBUG: suggestion_dict = {suggestion_dict}")

        retrieved_docs = reflection_response.split('\n')
        enriched_prompt = (
            f"{message}\n\n"
            "Additional knowledge/suggestions to follow/obey:\n"
            + "\n".join(f"{doc}" for doc in retrieved_docs)
        )

        # if FLAGS.debug:
        #     print(f"@@@DEBUG: enriched_prompt = {enriched_prompt}")

        response_str = initiate_chat_with_retry(
            agents["user"],
            agents["Coding"],
            message=enriched_prompt,
            temperature=temperature,
        )
        last_metrics=metrics
        # Store current metrics as previous before getting new ones
        previous_metrics = {
            'pec': metrics['pec'],
            'relax_pec': metrics['relax_pec'],
            'bleu': metrics['bleu'],
            'syntax': metrics.get('syntax', 0)
        }
        metrics = evaluate_pec_etc(response_str, row, only_bleu=FLAGS.only_BLEU, last_bleu=last_bleu, last_metrics=last_metrics)

        # if FLAGS.debug:
        #     print(f"@@@DEBUG: response_str = {response_str}")

        pec, relaxed_pec, bleu, syntax = metrics['pec'], metrics['relax_pec'], metrics['bleu'], metrics['syntax']
        bleu_scores.append(bleu)
        functionality_scores.append(pec)
        relaxed_functionality_scores.append(relaxed_pec)
        syntax_scores.append(syntax)

        print(f'###Record: \n###reflection_response: {reflection_response}\n###Assertions: {response_str}')
        print(f'###Record: \n###pec: {pec}\n###relaxed_pec: {relaxed_pec}\n###bleu: {bleu}\n###syntax: {syntax}')

        if (abs(pec - 1.0) < 1e-6 or abs(bleu - 1.0) < 1e-6) and (abs(initial_pec - 0.0) < 1e-6):
            # Save knowledge and Q-tree separately
            knowledge_str = save_knowledge(reflection_response, response_str, row, metrics, 
                                         initial_bleu, initial_relaxed_pec, last_bleu)
            
            # Save Q-tree if using Q-tree mode
            if use_qtree:
                save_qtree(qtree_builder, row, metrics, rules, previous_metrics, response_str)
            
            print(f'Saved knowledge (PEC 0--> 1)! :) {knowledge_str}')
            break
        elif (FLAGS.suggestion_saving_rule == "init_bleu" and bleu > initial_bleu) or (FLAGS.suggestion_saving_rule == "last_bleu" and bleu > last_bleu):
            knowledge_str = save_knowledge(reflection_response, response_str, row, metrics, 
                                         initial_bleu, initial_relaxed_pec, last_bleu)
            if use_qtree:
                save_qtree(qtree_builder, row, metrics, rules, previous_metrics, response_str)
            print(f'Saved knowledge (BLEU enhanced)! :) {knowledge_str}')
        elif FLAGS.suggestion_saving_rule == "all":
            knowledge_str = save_knowledge(reflection_response, response_str, row, metrics, 
                                         initial_bleu, initial_relaxed_pec, last_bleu)
            if use_qtree:
                save_qtree(qtree_builder, row, metrics, rules, previous_metrics, response_str)
            print(f'Saved knowledge (all)! :) {knowledge_str}')
        
        iter_cnt += 1
        last_bleu = bleu
        final_bleu = bleu

    fixable_indicator = 1 if initial_pec == 0 and pec == 1 else 0
    unfixable_indicator = 0 if (initial_pec == 0 and pec == 1 or initial_pec == 1) else 1

    if fixable_indicator == 1:
        final_bleu = bleu
    
    print(f'DEBUG: \n###final_bleu: {final_bleu}\n###initial_bleu: {initial_bleu}')

    record_statistics(iter_cnt, initial_pec, unfixable_indicator, fixable_indicator, final_bleu - initial_bleu, bleu_scores, functionality_scores, syntax_scores)

    saver.save_training_trace({
        "task_id": str(getattr(row, "task_id", "")),
        "design_name": str(getattr(row, "design_name", "")),
        "bleu": [float(value) for value in bleu_scores],
        "functionality": [float(value) for value in functionality_scores],
        "relaxed_functionality": [
            float(value) for value in relaxed_functionality_scores
        ],
        "syntax": [float(value) for value in syntax_scores],
        "iterations": max(len(functionality_scores) - 1, 0),
        "initial_functionality": float(initial_pec),
        "final_functionality": float(pec),
        "fixed": bool(fixable_indicator),
    })

    # Print the total times for GPT and JasperGold
    print(f'Total GPT time: {total_gpt_time:.2f} seconds')
    print(f'Total JasperGold time: {total_jaspergold_time:.2f} seconds')

# Note: extract_qtree_knowledge is deprecated - both Q-Tree and traditional approaches
# now use extract_suggestions_to_disk to maintain consistent knowledge format


def evaluate_pec_etc(response, row, only_bleu, last_bleu, last_metrics = None):
    """
    Evaluates the PEC and BLEU metrics for the generated response and reference solution.

    response (str): The LLM-generated assertions.
    row (object): An object containing the natural language prompt, testbench, and reference solutions.

    Returns:
    dict: A dictionary with 'pec' and 'bleu' metrics.
    """
    # if isinstance(response, ChatResult):
    #     response = response.content  # Adjust this based on the actual attribute that contains the string content
    
    # Initialize the evaluator
    # (1) Create the evaluator
    # if not only_bleu and last_bleu != similarity_metrics.get("bleu", 0):
    global total_jaspergold_time  # Use the global variable to accumulate JasperGold time

    if FLAGS.task == "nl2sva_human":
        evaluator = NL2SVAHumanEvaluator(
            llm_output_dir="",  # No need for an output directory in this context
            model_name=FLAGS.llm_model,  # No model name required here
            temp_dir=os.path.join(saver.logdir,"tmp"),  # Temporary directory for intermediate files
            save_dir=os.path.join(saver.logdir,"save"),  # Directory to save the final results
            parallel_jobs=1,  # Set to 1 for simplicity
            cleanup_temp_files=True,
            debug=FLAGS.debug,
        )
    elif FLAGS.task == "nl2sva_machine" or FLAGS.task == "nl2sva_opencore":
        evaluator = NL2SVAMachineEvaluator(
            task = FLAGS.task,
            llm_output_dir="",  # No need for an output directory in this context
            model_name=FLAGS.llm_model,  # No model name required here
            temp_dir=os.path.join(saver.logdir,"tmp"),  # Temporary directory for intermediate files
            save_dir=os.path.join(saver.logdir,"save"),  # Directory to save the final results
            parallel_jobs=1,  # Set to 1 for simplicity
            cleanup_temp_files=True,
            debug=FLAGS.debug,
        )
    else:
        raise ValueError("Invalid task specified in FLAGS.task")

    # Evaluate text similarity (BLEU score)
    # print(f"###response: {response}")
    # print(f"###reference solution: {row.ref_solution}")
    similarity_metrics = evaluator.calculate_similiarty_metric(response, row.ref_solution, original_setting = False)
    # functionality_score = 0
    # relaxed_functionality_score = 0
    # syntax_score = 0
    
    if last_metrics and only_bleu:
        return last_metrics
    else:
        # Create a dummy LMResult for evaluation
        # lm_result = LMResult(
        #     experiment_id=FLAGS.dataset_path.split(".csv")[0].split("/")[-1],
        #     task_id=row.task_id,
        #     model_name=FLAGS.llm_model,
        #     response=response,
        #     ref_solution=row.ref_solution,
        #     user_prompt=row.prompt,
        #     design_rtl="\n",
        #     output_tb=row.testbench,
        #     cot_response="\n",
        # )

        if FLAGS.task == "nl2sva_machine" or FLAGS.task == "nl2sva_human":
            lm_result = LMResult(
                experiment_id=FLAGS.dataset_path.split(".csv")[0].split("/")[-1],
                task_id=row.task_id,
                model_name=FLAGS.llm_model,
                response=response,
                ref_solution=row.ref_solution,
                user_prompt=row.prompt,
                design_rtl="\n",
                output_tb=row.testbench,
                cot_response="\n",
            )
        elif FLAGS.task == "nl2sva_opencore":
            post_ref_solution = f"assert property({row.ref_solution});"
            safe_design_name = row.design_name.replace('/', '_')
            lm_result = LMResult(
                experiment_id=FLAGS.dataset_path.split(".csv")[0].split("/")[-1],
                task_id=safe_design_name,
                model_name=FLAGS.llm_model,
                response=response,
                ref_solution=post_ref_solution,
                user_prompt=row.prompt,
                output_tb="\n",
                design_rtl="\n",
                cot_response="cot_response\n",
            )
        else:
            raise NotImplementedError(f"Task '{FLAGS.task}' is not implemented")

        # Decide which method to use for functionality scoring based on FLAGS.PEC_method
        if FLAGS.PEC_method == "JasperGold":
            # Evaluate functionality using JasperGold
            start_time = time.time()  # Start time for JasperGold
            jg_results = evaluator.evaluate_jg([lm_result], with_rtl_design=True)
            total_jaspergold_time += time.time() - start_time  # Calculate and add elapsed time to the total
            functionality_score = jg_results[0].functionality if jg_results else 0
            relaxed_functionality_score = jg_results[0].func_relaxed if jg_results else 0
            syntax_score = jg_results[0].syntax if jg_results else 0
        elif FLAGS.PEC_method == "GPT":
            raise ValueError("Invalid PEC method specified in FLAGS.PEC_method")
        elif FLAGS.PEC_method == "no_PEC":
            functionality_score = 0
        else:
            raise ValueError("Invalid PEC method specified in FLAGS.PEC_method")
        
        # print(f'Print Metrics:\n ###pec: {functionality_score}; \n ###bleu: {similarity_metrics.get("bleu", 0)}')
        metrics = {
            "syntax": syntax_score,
            "pec": functionality_score,
            "relax_pec": relaxed_functionality_score,
            "bleu": similarity_metrics.get("bleu", 0)}
    
    # Collect the metrics
    
    return metrics

def extract_suggestions_2(text):
    # Define the regular expression pattern to match suggestions
    pattern = r'(- .+\n)+'
    
    # Use re.search to find the suggestions part
    match = re.search(pattern, text)
    
    if match:
        return match.group().strip()
    else:
        return "No suggestions found."

def prompt_self_reflection(user_agent, reflection_agent, row, response, sorted_suggestions=None):
    """
    Prompts the self-reflection agent to compare the generated and reference SVAs and provide suggestions.

    Parameters:
    user_agent (UserProxyAgent): The user proxy agent.
    reflection_agent (AssistantAgent): The self-reflection agent.
    row (object): An object containing the natural language prompt, testbench, and reference solutions.
    response (str): The initial response from the LLM-generated assertions.
    sorted_suggestions (OrderedDict): The sorted suggestions with their metrics.

    Returns:
    str: The new suggestions set from the self-reflection agent.
    """
    # Define token limits for each LLM
    token_limits = {
        "gpt-4": 8192,
        "gpt-3.5-turbo": 4096,
        "llama3-70b": 8000
    }

    # Choose the appropriate token limit
    token_limit = token_limits.get(FLAGS.llm_model, 8192)  # Default to 8192 if model name is not found
    # print(f"@@@DEBUG token limit = {token_limit}")

    prompt_message = (
        f"The natural language question for assertion generation is: \n{row.prompt}\n"
        f"The testbench is: \n{row.testbench} \n"
        f"Compare and reflect upon the differences between the LLM-generated assertions and the reference assertions. "
        f"Provide a list of suggestions for future assertion generations based on these reflections. Note that we want you to generate the suggestions that could directly fix the gap and generate referenced solution by appending your suggestions.\n"
        f"LLM response: {response}; \nReference: {row.ref_solution} \n"
        f"Provide a list of suggestions, each in one sentence, applicable to all future assertion generations. "
        f"Base these suggestions on the differences between the LLM-generated assertions and the reference assertions. "
        f"The number of suggestions should correspond to the number of different signals or operators identified. "
    )
    if FLAGS.is_constrain_number:
        prompt_message += f"Ideally, the total number of suggestions should be fewer than {FLAGS.num_constrain}. Prioritize the most important suggestions. "
    
    if FLAGS.task == "nl2sva_human" or FLAGS.task == "nl2sva_machine":
        prompt_message += (
            f"Please consider every part of the input like natural language, testbench and do NOT consider the signal names in the suggestion part."
            f"Output each suggestion as a separate line starting with '- ' to clearly distinguish each suggestion.\n\n"
            f"Examples of useful suggestions:\n"
            f"- If the natural language query contains some signal names, just use the signals instead of adding more you imagine. For example, if the current natural language asks you to use a latency threshold, just extract one signal corresponding to that signal instead of overthinking and using additional signals.\n"
            f"- Do NOT use the implication operator '|->' if possible, i.e. only use '|->' if simpler alternatives are not enough. In such cases, directly write combinatorial logic using '&&', '!==', etc.\n"
            f"- If the natural language already contains some signal names, for example, if the natural language query contains the following sentence: 'Use the signals 'tb_gnt', 'last_gnt', 'hold', and 'tb_req'.' You may ignore/miss some variables such as hold, i.e. you don't have to use every signal in the query.\n"
            f"- Do NOT add the comments to the assertions.\n"
        )
    elif FLAGS.task == "nl2sva_opencore":
            prompt_message += (
            f"Please consider every part of the input like natural language, testbench and do NOT consider the signal names in the suggestion part."
            f"Output each suggestion as a separate line starting with '- ' to clearly distinguish each suggestion.\n\n"
            f"Examples of useful suggestions:\n"
            f"- Do NOT use the operators like ##[2] because PEC checker could recognize it as a syntax error.\n"
            f"- If the natural language uses the signals like x,y etc., do not introduce unseen signals like '$x' or '$y'. Instead, please just use x,y in the generated SVA.\n"
            f"- If the natural language query contains phrases like 'after three clock cycles', then your SVA assertion should use '#3' to express this relationship instead of '#[3]'.\n"
            # f"- If the natural language query contains phrases like 'X must occur immediately after sequence Y' or 'X must be high on the cycle immediately following sequence Y', then your SVA assertion should use the implication operator '|->' to express this relationship. For example: 'sequence_Y |-> X'.\n"
            f"- If the natural language contains the expression like 'within one clock cycle after x', please use '##1' before '|->', i.e.,'##1 1) |->', instead of appending '##1' after '|->', i.e., '|=> ##1'.\n"
            f"- If the natural language looks like 'that if cond_a, then after exactly 3 clock cycles, cond_b; and if this condition holds, then cond_c', your answer should be something like '(cond_a ##3 cond_b) |-> cond_c' instead of 'cond_a |-> ##3 cond_b && ##4 cond_c'. \n"
            f"- If the natural language query contains 'cond_a is asserted exactly four clock cycles after cond_b', then your answer should be something like '(cond_b ##4 1) |-> cond_a' instead of 'cond_b |=> ##4 cond_a'.\n"
            f"- If the natural language query contains some signal names, just use the signals instead of adding more you imagine. For example, if the current natural language asks you to use a latency threshold, just extract one signal corresponding to that signal instead of overthinking and using additional signals.\n"
            f"- If the natural language already contains some signal names, for example, if the natural language query contains the following sentence: 'Use the signals 'tb_gnt', 'last_gnt', 'hold', and 'tb_req'.' You may ignore/miss some variables such as hold, i.e. you don't have to use every signal in the query.\n"
            f"- Do NOT add the comments to the assertions.\n"
        )

    if sorted_suggestions and FLAGS.carryover:
        carryover_message = "\nI have some suggestions sets along with their corresponding scores. The suggestions sets are arranged in ascending order based on their scores, where higher scores indicate better quality:\n"
        added_suggestions = 0
        for i, (iter_index, suggestion_set) in enumerate(reversed(sorted_suggestions)):  # Reverse the sorted suggestions to get ascending order
            if added_suggestions >= FLAGS.num_carryover:
                break
            if FLAGS.only_BLEU:
                suggestion_block = (
                    f"\nSuggestions Set {i + 1}:\n"
                    f"{suggestion_set['suggestions']}\n"
                    f"BLEU Score: {suggestion_set['BLEU']}\n"
                )
            else:
                suggestion_block = (
                    f"\nSuggestions Set {i + 1}:\n"
                    f"{suggestion_set['suggestions']}\n"
                    f"BLEU Score: {suggestion_set['BLEU']}\n"
                    f"Functionality Score: {suggestion_set['functionality']}\n"
                    f"Relaxed Functionality Score: {suggestion_set['relaxed_functionality']}\n"
                )

            # print(f"@@@DEBUG: Tokens = {count_tokens(prompt_message + carryover_message)}")
            # print(f"@@@DEBUG: carryover_message before truncation = {carryover_message}, tokens = {count_tokens(carryover_message)}")
            # if count_tokens(prompt_message + carryover_message + suggestion_block) > token_limit:
            #     break
            # else:
            carryover_message += suggestion_block
            added_suggestions += 1
        
        # print(f"@@@DEBUG: carryover_message = {carryover_message}, tokens = {count_tokens(carryover_message)}")
        prompt_message += carryover_message

        prompt_message += (
            "\n\nLastly, give me a new set of suggestions that is different from suggestions above, "
            f"and has evaluation values including BLEU Score"
            f"{', Functionality Score, Relaxed Functionality Score' if not FLAGS.only_BLEU else ''} higher than any of the above. "
            "Do not write code. The output must end with a set of suggestions where BLEU Score"
            f"{', Functionality Score, Relaxed Functionality Score' if not FLAGS.only_BLEU else ''} are numerical values." 
            # f"Please control the size of the set of suggestions in five. If you have more suggestions, just pick the top five ones."
        )

    # Ensure the prompt is within the token limit
    # prompt_length = count_tokens(prompt_message)
    # if prompt_length > token_limit:
    #     prompt_message = truncate_suggestions(prompt_message, token_limit)

    # Initiate chat with retry logic
    suggestions = initiate_chat_with_retry(user_agent, reflection_agent, message=prompt_message)
    suggestions_extracted = extract_suggestions_2(suggestions)

    if FLAGS.debug:
        print(f"@@@DEBUG:Reflection prompt message = {prompt_message}")
        print(f"@@@DEBUG:suggestions_extracted = {suggestions_extracted}")

    return suggestions_extracted


def enrich_reflection_prompt(reflection_response):
    """
    Enriches the prompt dynamically for the self-reflection agent to introduce variations for better suggestions.

    Parameters:
    reflection_response (object): The response from the self-reflection agent.

    Returns:
    None
    """
    additional_examples = [
        "Another example: If the query specifies a reset condition, do not add extra reset signals unless explicitly mentioned.",
        "Another example: If the query specifies 'when signal X is high', do not add extra conditions like 'when signal Y is low'."
    ]
    reflection_response += "\n".join(additional_examples)
    return reflection_response


def save_knowledge(reflection_response, response_str, row, metrics, 
                   initial_bleu, initial_relaxed_pec, last_bleu):
    """
    Save learning knowledge in standard format.
    
    Parameters:
    reflection_response: Response from reflection agent (suggestions/rules)
    response_str: The generated assertion
    row: Data row with task info
    metrics: Current metrics dict
    initial_bleu: Initial BLEU score
    initial_relaxed_pec: Initial relaxed PEC score
    last_bleu: Previous iteration's BLEU score
    
    Returns:
    str: Formatted knowledge string
    """
    knowledge_str = extract_suggestions_to_disk(reflection_response, response_str, row, metrics, 
                                               initial_bleu, initial_relaxed_pec, last_bleu)
    saver.save_knowledge(knowledge_str)
    saver.dump_knolwedge_to_disk()
    return knowledge_str


def save_qtree(qtree_builder, row, metrics, rules, previous_metrics = None, response_str = None):
    """
    Save Q-tree structure for analysis and write to disk immediately.
    
    Parameters:
    qtree_builder: The QTreeBuilder instance
    row: Data row with task info
    metrics: Current metrics dict (final metrics after fixing)
    rules: Aggregated rules from Q-tree
    previous_metrics: Previous iteration's metrics (optional)
    response_str: The generated assertion (optional)
    """
    if qtree_builder is None:
        return
    
    # For opencore dataset, use design_name as task_id (consistent with inference)
    if FLAGS.task == "nl2sva_opencore":
        task_id_for_qtree = getattr(row, 'design_name', '').replace('/', '_')
    else:
        task_id_for_qtree = row.task_id
    
    # Get the qtree data using the builder's method
    qtree_data = qtree_builder.get_qtree_data(task_id_for_qtree)
    
    # Store rules in qtree_data but not metrics (they're stored separately)
    qtree_data["rules"] = rules
    # qtree_data["Generated SVA"] = response_str
    
    # Save the qtree correction (appends to list)
    # Include design_name and prompt if they exist in the row
    design_name = getattr(row, 'design_name', None)
    prompt = getattr(row, 'prompt', None)
    testbench = getattr(row, 'testbench', None)
    
    saver.save_qtree_correction(
        qtree_data, 
        task_id_for_qtree,  # Use the corrected task_id
        design_name=design_name,
        prompt=prompt,
        testbench=testbench,
        generated_sva=response_str,
        previous_metrics=previous_metrics,
        final_metrics=metrics
    )
    
    # Write qtrees to disk immediately (overwrites previous qtrees.pkl, doesn't touch suggestions.pkl)
    saver.dump_qtrees_only()


def extract_suggestions_to_disk(reflection_response, response, row, metrics, initial_bleu, initial_relaxed_pec, last_bleu):
    """
    Extracts and formats learned suggestions from the reflection agent's response.

    Parameters:
    reflection_response (object): The response from the self-reflection agent.
    response (str): The initial response from the LLM-generated assertions.
    row (object): An object containing the natural language prompt, testbench, and reference solutions.

    Returns:
    """
    # suggestions = reflection_response.chat_history[-1]['content'].split('\n')
    # suggestions = reflection_response.split('\n')
    delimiter = "<---->"
    # formatted_suggestions = [f"{response}\n{row.ref_solution}\n{suggestion}" for suggestion in suggestions if suggestion.startswith("- ")]
    knowledge_str = (
        f"Question:Create a SVA assertion that checks: {row.prompt}{delimiter}"
        f"Answer:{response}{delimiter}"
        f"Suggestions:{reflection_response}{delimiter}"
        f"BLEU:{metrics['bleu']}{delimiter}"
        f"Functionality:{metrics['pec']}{delimiter}"
        f"Relaxed Functionality:{metrics['relax_pec']}{delimiter}"
        f"Syntax:{metrics['syntax']}{delimiter}"
        f"Last BLEU:{last_bleu}{delimiter}"
        f"Initial BLEU:{initial_bleu}{delimiter}"
        f"Initial Relaxed Functionality:{initial_relaxed_pec}{delimiter}"
        f"Task ID:{row.task_id}{delimiter}"
        f"Reference Answer:{row.ref_solution}")
    return knowledge_str # TODO: directly put all the suggestions. Need to change it later


def extract_qtree_to_disk(qtree_builder, response, row, metrics, initial_bleu, initial_relaxed_pec, last_bleu, rules):
    """
    Extracts and formats Q-tree data similar to extract_suggestions_to_disk.
    
    Parameters:
    qtree_builder: The QTreeBuilder instance containing the Q-tree structure
    response (str): The LLM-generated assertions
    row (object): An object containing the natural language prompt, testbench, and reference solutions
    metrics (dict): Current metrics including pec, relax_pec, bleu, syntax
    initial_bleu: Initial BLEU score
    initial_relaxed_pec: Initial relaxed PEC score
    last_bleu: Previous iteration's BLEU score
    rules (list): Aggregated rules from the Q-tree
    
    Returns:
    str: Formatted Q-tree knowledge string
    """
    delimiter = "<---->"
    
    # Extract Q-tree specific information
    qtree_summary = {
        "total_nodes": len(qtree_builder.nodes),
        "exploratory_questions": sum(1 for n in qtree_builder.nodes.values() if n.level.value == "exploratory"),
        "specific_questions": sum(1 for n in qtree_builder.nodes.values() if n.level.value == "specific_analysis"),
        "rule_nodes": sum(1 for n in qtree_builder.nodes.values() if n.level.value == "rule_generation"),
        "total_rules": len(rules)
    }
    
    # Format Q-tree nodes for storage
    qtree_nodes_str = []
    for node_id, node in qtree_builder.nodes.items():
        node_str = f"[{node.level.value}] {node.question}"
        if node.answer:
            node_str += f" => {node.answer[:100]}..." if len(node.answer) > 100 else f" => {node.answer}"
        if node.rules_generated:
            node_str += f" (Rules: {len(node.rules_generated)})"
        qtree_nodes_str.append(node_str)
    
    # Create the knowledge string similar to extract_suggestions_to_disk
    knowledge_str = (
        f"Question:Create a SVA assertion that checks: {row.prompt}{delimiter}"
        f"Answer:{response}{delimiter}"
        f"Q-Tree Rules:{chr(10).join(rules)}{delimiter}"
        f"Q-Tree Summary:Nodes={qtree_summary['total_nodes']}, "
        f"Exploratory={qtree_summary['exploratory_questions']}, "
        f"Specific={qtree_summary['specific_questions']}, "
        f"Rules={qtree_summary['total_rules']}{delimiter}"
        f"Q-Tree Structure:{chr(10).join(qtree_nodes_str[:10])}{delimiter}"  # First 10 nodes
        f"BLEU:{metrics['bleu']}{delimiter}"
        f"Functionality:{metrics['pec']}{delimiter}"
        f"Relaxed Functionality:{metrics['relax_pec']}{delimiter}"
        f"Syntax:{metrics['syntax']}{delimiter}"
        f"Last BLEU:{last_bleu}{delimiter}"
        f"Initial BLEU:{initial_bleu}{delimiter}"
        f"Initial Relaxed Functionality:{initial_relaxed_pec}{delimiter}"
        f"Task ID:{row.task_id}{delimiter}"
        f"Reference Answer:{row.ref_solution}"
    )
    
    return knowledge_str


def adjust_temperature(iter_cnt, bleu, last_bleu):
    if FLAGS.train_temp_setting == "random":
        # If the setting is to change only when BLEU scores are the same and iteration count is greater than 0
        if FLAGS.change_only_bleu_same:
            if iter_cnt > 0 and bleu == last_bleu:
                temperature = random.uniform(FLAGS.low_temp, FLAGS.high_temp)  # Assign a random temperature between 0 and 1.0
                if FLAGS.debug:
                    print(f"@@@Assigning random temperature: {temperature}")
            else:
                temperature = FLAGS.temperature  # Use the fixed temperature from FLAGS
        else:
            temperature = random.uniform(FLAGS.low_temp, FLAGS.high_temp)  # Always assign a random temperature between 0 and 1.0
            if FLAGS.debug:
                print(f"@@@Assigning random temperature: {temperature}")
    elif FLAGS.train_temp_setting == "fixed":
        temperature = FLAGS.temperature  # Use the fixed temperature from FLAGS
    else:
        raise ValueError("Invalid train_temp_setting. It should be either 'random' or 'fixed'.")

    return temperature

# def record_statistics(row_id, iter_cnt, initial_pec, unfixable_indicator, fixable_indicator, partly_fixable_indicator, delta_bleu, delta_relaxed_pec):
#     """
#     Records the statistics of the self-learning process.

#     Parameters:
#     row_id (int): The ID of the current example.
#     iter_cnt (int): The number of iterations performed.
#     initial_pec (int): Initial PEC value (1 if PEC=1 initially, 0 otherwise).
#     unfixable_indicator (int): Indicator if PEC is always 0 across all iterations.
#     fixable_indicator (int): Indicator if PEC changes from 0 to 1 across iterations.
#     delta_bleu (float): The change in BLEU score from initial to final.

#     Returns:
#     None
#     """
#     # saver.save_stats("iterations", iter_cnt, row_id)
#     # saver.save_stats("initial_correct_indicator", initial_pec, row_id)
#     # saver.save_stats("unfixable_indicator", unfixable_indicator, row_id)
#     # saver.save_stats("fixable_indicator", fixable_indicator, row_id)
#     # saver.save_stats("partly_fixable_indicator", fixable_indicator, row_id)
#     # if fixable_indicator:
#     #     saver.save_stats("fixable_iterations", iter_cnt, row_id)
#     # saver.save_stats("delta_bleu", delta_bleu, row_id)
#     # # if delta_pec != 0:
#     # # saver.save_stats("delta_pec", delta_pec, row_id)
#     # # if delta_relaxed_pec != 0:
#     # saver.save_stats("delta_relaxed_pec", delta_relaxed_pec, row_id)
#     saver.save_stats("iterations", iter_cnt)
#     saver.save_stats("initial_correct_indicator", initial_pec)
#     saver.save_stats("unfixable_indicator", unfixable_indicator)
#     saver.save_stats("fixable_indicator", fixable_indicator)
#     saver.save_stats("partly_fixable_indicator", fixable_indicator)
#     if fixable_indicator:
#         saver.save_stats("fixable_iterations", iter_cnt)
#     saver.save_stats("delta_bleu", delta_bleu)
#     # if delta_pec != 0:
#     # saver.save_stats("delta_pec", delta_pec)
#     # if delta_relaxed_pec != 0:
#     saver.save_stats("delta_relaxed_pec", delta_relaxed_pec)

def record_statistics(iter_cnt, initial_pec, unfixable_indicator, fixable_indicator, delta_bleu, bleu_scores, functionality_scores, syntax_scores):
    saver.save_stats("iterations", iter_cnt)
    saver.save_stats("initial_correct_indicator", initial_pec)
    saver.save_stats("unfixable_indicator", unfixable_indicator)
    saver.save_stats("fixable_indicator", fixable_indicator)
    if fixable_indicator:
        saver.save_stats("fixable_iterations", iter_cnt)
    saver.save_stats("delta_bleu", delta_bleu)

    # Determine the maximum number of iterations
    max_iterations = FLAGS.num_iter  # Assuming FLAGS.num_iter is the maximum number of iterations

    # Save metrics for each iteration, filling in missing values if necessary
    # for i in range(1, max_iterations + 2):
    for i in range(1, len(bleu_scores) + 1):
        if i <= len(bleu_scores):
            saver.save_stats(f"iteration_{i}_bleu", bleu_scores[i-1])
        else:
            saver.save_stats(f"iteration_{i}_bleu", bleu_scores[-1] if bleu_scores else None)

        if i <= len(functionality_scores):
            saver.save_stats(f"iteration_{i}_functionality", functionality_scores[i-1])
        else:
            saver.save_stats(f"iteration_{i}_functionality", functionality_scores[-1] if functionality_scores else None)

        if i <= len(syntax_scores):
            saver.save_stats(f"iteration_{i}_syntax", syntax_scores[i-1])
        else:
            saver.save_stats(f"iteration_{i}_syntax", syntax_scores[-1] if syntax_scores else None)