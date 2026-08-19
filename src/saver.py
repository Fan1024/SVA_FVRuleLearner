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
from config import FLAGS
from utils import get_ts, create_dir_if_not_exists, save, save_pickle
from utils import (
    get_src_path,
    get_model_info_as_str,
    extract_config_code,
    plot_scatter_line,
    plot_dist,
    save_pickle,
    dirname,
    estimate_model_size,
    set_ts,
    print_gpu_free_mem_info,
    get_gpu_info,
    print_stats,
)
import json, argparse


from collections import OrderedDict, defaultdict
from pprint import pprint
from os.path import join, dirname, basename
import torch
import networkx as nx
import numpy as np
import time, os, pickle


class MyTimer:
    def __init__(self) -> None:
        self.start = time.time()

    def elapsed_time(self):
        end = time.time()
        minutes, seconds = divmod(end - self.start, 60)

        return int(minutes)


class Saver(object):
    def __init__(self):

        parser = argparse.ArgumentParser(description="Run JG-based Evaluation of FVEval-SVAGen Results")
        parser.add_argument("--src_examples", type=str, required=False)
        parser.add_argument("--llm_model", type=str, required=False)
        parser.add_argument("--group_id", type=str, required=False)
        parser.add_argument("--logdir", type=str, required=False)
        args = parser.parse_args()

        if args.src_examples is not None:
            setattr(FLAGS, 'src_examples', [args.src_examples])  # Wrap in list if it's a single string
        elif args.src_examples is not None and args.src_examples.startswith('['):
            setattr(FLAGS, 'src_examples', eval(args.src_examples))  # Only use eval if it's a list representation
        if args.llm_model is not None:
            setattr(FLAGS, 'llm_model', args.llm_model)
        if args.group_id is not None:
            setattr(FLAGS, 'group_id', args.group_id)
        if args.logdir is not None:
            self.logdir = args.logdir
        else:
            self.logdir = join(
                get_src_path(),
                'logs',
                # '{}_{}_{}_{}_{}_{}_{}'.format(FLAGS.norm_method, FLAGS.task, FLAGS.subtask, FLAGS.tag, FLAGS.target, model_str, get_ts()))
                '{}_{}_{}_{}'.format(FLAGS.global_task, get_ts(), FLAGS.hostname, FLAGS.user),
            )

        self.accelerator = None

        self.pidstr = ''

        context = NoOpContextManager()

        with context:
            create_dir_if_not_exists(self.logdir)
            self.model_info_f = self._open(f'model_info{self.pidstr}.txt')
            self.plotdir = join(self.logdir, 'plot')
            create_dir_if_not_exists(self.plotdir)
            self.objdir = join(self.logdir, 'obj')
            self._log_model_info()
            self._save_conf_code()
            self.timer = MyTimer()
            self.all_messages = set()
            self.msg_type_count = defaultdict(int)
            print('Logging to:\n{}'.format(self.logdir))
            print(basename(self.logdir))

        self.learned_knowledge = []  # TODO --> KG
        self.qtree_corrections = []  # Store qtrees that lead to corrections

        self.stats = defaultdict(list)
        
        # Track suggestion usage and outcomes
        self.suggestion_tracking = {
            'with_suggestions': [],  # List of task_ids that used suggestions
            'without_suggestions': [],  # List of task_ids that didn't use suggestions
            'with_suggestions_solved': [],  # List of task_ids that used suggestions and solved
            'without_suggestions_solved': [],  # List of task_ids that didn't use suggestions and solved
        }

    def get_device(self):
        return FLAGS.device

    def _open(self, f):
        return open(join(self.logdir, f), 'w')

    def close(self):

        self.print_stats()
        
        # Print suggestion usage statistics
        if (len(self.suggestion_tracking['with_suggestions']) > 0 or 
            len(self.suggestion_tracking['without_suggestions']) > 0):
            self.print_suggestion_statistics()

        self.log_info(self.logdir)
        self.log_info(basename(self.logdir))
        if hasattr(self, 'log_f'):
            self.log_f.close()
        if hasattr(self, 'log_e'):
            self.log_e.close()
        if hasattr(self, 'log_d'):
            self.log_d.close()
        if hasattr(self, 'results_f'):
            self.results_f.close()

    def get_log_dir(self):
        return self.logdir

    def get_plot_dir(self):
        create_dir_if_not_exists(self.plotdir)
        return self.plotdir

    def get_obj_dir(self):
        create_dir_if_not_exists(self.objdir)
        return self.objdir

    def log_list_of_lists_to_csv(self, lol, fn, delimiter=','):
        import csv

        fp = open(join(self.logdir, fn), 'w+')
        csv_writer = csv.writer(fp, delimiter=delimiter)
        for l in lol:
            csv_writer.writerow(l)
        fp.close()

    def log_dict_of_dicts_to_csv(self, fn, csv_dict, csv_header, delimiter=','):
        import csv

        fp = open(join(self.logdir, f'{fn}.csv'), 'w+')
        f_writer = csv.DictWriter(fp, fieldnames=csv_header)
        f_writer.writeheader()
        for d, value in csv_dict.items():
            if d == 'header':
                continue
            f_writer.writerow(value)
        fp.close()

    def save_emb_accumulate_emb(self, data_key, d, convert_to_np=False):
        if not hasattr(self, 'emb_dict'):
            self.emb_dict = OrderedDict()

        if convert_to_np:
            new_d = {}
            for key, val in d.items():
                if torch.is_tensor(val):
                    val = val.detach().cpu().numpy()
                new_d[key] = val
            d = new_d

        self.emb_dict[data_key] = d

    def save_emb_save_to_disk(self, p):
        assert hasattr(self, 'emb_dict')
        filepath = join(self.objdir, p)
        create_dir_if_not_exists(dirname(filepath))
        save_pickle(self.emb_dict, filepath, print_msg=True)

    def save_emb_dict(self, d, p, convert_to_np=False):
        if not hasattr(self, 'save_emb_cnt'):
            self.save_emb_cnt = 0

        if convert_to_np:
            new_d = {}
            for key, val in d.items():
                if torch.is_tensor(val):
                    val = val.detach().cpu().numpy()
                new_d[key] = val
            d = new_d

        filepath = join(self.objdir, f'{self.save_emb_cnt}_{p}')
        create_dir_if_not_exists(dirname(filepath))
        save_pickle(d, filepath, print_msg=True)
        self.save_emb_cnt += 1

    def log_dict_to_json(self, dictionary, fn):
        import json

        # as requested in comment
        with open(join(self.get_obj_dir(), fn), 'w') as file:
            file.write(json.dumps(dictionary))

    def log_model_architecture(self, model):
        # print(model)
        if hasattr(self, 'has_logged_arch') and self.has_logged_arch:
            return  # avoid logging again and again within one python process
        if not hasattr(self, 'has_logged_arch'):
            self.has_logged_arch = True
        self.model_info_f.write('{}\n'.format(model))
        estimate_model_size(model, 'whole model', self)
        self.model_info_f.flush()
        # self.model_info_f.close()  # TODO: check in future if we write more to it

    # def log_info(self, s, silent=False, build_str=None):
    #     if not silent:
    #         print(s)
    #     if not hasattr(self, 'log_f'):
    #         self.log_f = self._open(f'log{self.pidstr}.txt')
    #     try:
    #         self.log_f.write('{}\n'.format(s))
    #         self.log_f.flush()
    #     except:
    #         raise RuntimeError()
    #     if build_str is not None:
    #         assert type(build_str) is str
    #         build_str += '{}\n'.format(s)
    #         return build_str

    def log_info(self, s, silent=False, build_str=None):
        # Pretty-printing logic
        if isinstance(s, (list, dict)):
            s = json.dumps(s, indent=4)
        elif hasattr(s, 'chat_history'):
            s = json.dumps(s.chat_history, indent=4)

        if not silent:
            print(s)
        if not hasattr(self, 'log_f'):
            self.log_f = self._open(f'log{self.pidstr}.txt')
        try:
            self.log_f.write('{}\n'.format(s))
            self.log_f.flush()
        except:
            raise RuntimeError()
        if build_str is not None:
            assert isinstance(build_str, str)
            build_str += '{}\n'.format(s)
            return build_str

    def log_info_once(self, s, silent=False):
        if s not in self.all_messages:
            self.all_messages.add(s)
            self.log_info(s, silent)

    def log_info_at_most(self, s, msg_type, times, silent=False):
        if self.msg_type_count[msg_type] < times:
            self.log_info(s, silent)
            self.msg_type_count[msg_type] += 1

    def info(self, s, silent=False):
        elapsed = self.timer.elapsed_time()
        if not silent:
            print(f'[{elapsed}m] INFO: {s}')
        if not hasattr(self, 'log_f'):
            self.log_f = self._open('log.txt')
        self.log_f.write(f'[{elapsed}m] INFO: {s}\n')
        self.log_f.flush()

    def error(self, s, silent=False):
        elapsed = self.timer.elapsed_time()
        if not silent:
            print(f'[{elapsed}m] ERROR: {s}')
        if not hasattr(self, 'log_e'):
            self.log_e = self._open('error.txt')
        self.log_e.write(f'[{elapsed}m] ERROR: {s}\n')
        self.log_e.flush()

    def warning(self, s, silent=False):
        elapsed = self.timer.elapsed_time()
        if not silent:
            print(f'[{elapsed}m] WARNING: {s}')
        if not hasattr(self, 'log_f'):
            self.log_f = self._open('log.txt')
        self.log_f.write(f'[{elapsed}m] WARNING: {s}\n')
        self.log_f.flush()

    def debug(self, s, silent=True):
        elapsed = self.timer.elapsed_time()
        if not silent:
            print(f'[{elapsed}m] DEBUG: {s}')
        if not hasattr(self, 'log_d'):
            self.log_d = self._open('debug.txt')
        self.log_d.write(f'[{elapsed}m] DEBUG: {s}\n')
        self.log_d.flush()

    def log_info_new_file(self, s, fn):
        # print(s)
        log_f = open(join(self.logdir, fn), 'a')
        log_f.write('{}\n'.format(s))
        log_f.close()

    def save_dict(self, d, p, subfolder=''):
        filepath = join(self.logdir, subfolder, p)
        create_dir_if_not_exists(dirname(filepath))
        save_pickle(d, filepath, print_msg=True)
        # print(f'dict of keys {d.keys()} saved to {filepath}')

    def _save_conf_code(self):
        with open(join(self.logdir, 'config.py'), 'w') as f:
            f.write(extract_config_code())
        p = join(self.get_log_dir(), 'FLAGS')
        save({'FLAGS': FLAGS}, p, print_msg=False)

    def save_graph_as_gexf(self, g, fn):
        nx.write_gexf(g, join(self.get_obj_dir(), fn))

    def save_overall_time(self, overall_time):
        self._save_to_result_file(overall_time, 'overall time')

    def save_exception_msg(self, msg):
        with self._open('exception.txt') as f:
            f.write('{}\n'.format(msg))

    def save_dict_as_pickle(self, d, name):
        p = join(self.get_obj_dir(), name)
        p = save(d, p, print_msg=True, use_klepto=False)
        self.log_info(f'Saving dict {name}')
        return p

    def _get_model_str(self):
        li = []
        key_flags = [FLAGS.model, FLAGS.dataset]
        for f in key_flags:
            li.append(str(f))
        rtn = '_'.join(li)
        return f'{rtn}'

    def _log_model_info(self):
        s = get_model_info_as_str(FLAGS)
        print(s)
        self.model_info_f.write(s)
        self.model_info_f.write('\n\n')
        self.model_info_f.flush()
        # self.writer.add_text('model_info_str', s)

    def log_new_FLAGS_to_model_info(self):
        self.model_info_f.write('----- new model info after loading\n')
        self._log_model_info()
        self._save_conf_code()

    def _save_to_result_file(self, obj, name=None, to_print=False):
        if not hasattr(self, 'results_f'):
            self.results_f = self._open('results.txt')
        if type(obj) is dict or type(obj) is OrderedDict:
            # self.f.write('{}:\n'.format(name))
            # for key, value in obj.items():
            #     self.f.write('\t{}: {}\n'.format(key, value))
            pprint(obj, stream=self.results_f)
        elif type(obj) is str:
            if to_print:
                print(obj)
            self.results_f.write('{}\n'.format(obj))
        else:
            self.results_f.write('{}: {}\n'.format(name, obj))
        self.results_f.flush()

    def _shrink_space_pairs(self, pairs):
        for _, pair in pairs.items():
            # print(pair.__dict__)
            pair.shrink_space_for_save()
            # pass
            # print(pair.__dict__)
            # exit(-1)
        return pairs

    def save_knowledge(self, suggestions):
        self.learned_knowledge.append(suggestions)  # TODO: maybe de-duplicate

    def dump_knolwedge_to_disk(self):
        # Define the pickle file name
        pkl_filename = os.path.join(self.logdir, "suggestions.pkl")

        # # Load existing data from the pickle file if it exists
        # if os.path.exists(pkl_filename):
        #     with open(pkl_filename, "rb") as pkl_file:
        #         existing_data = pickle.load(pkl_file)
        # else:
        #     existing_data = []

        # Append the new suggestions
        existing_data = self.learned_knowledge

        # Save the updated data back to the pickle file
        with open(pkl_filename, "wb") as pkl_file:
            pickle.dump(existing_data, pkl_file)

        self.log_info(f'Save to {pkl_filename} of len {len(existing_data)}')
        
        # Also save qtree corrections if they exist
        if self.qtree_corrections:  # Save if any qtrees exist, regardless of flag
            self.dump_qtree_corrections_to_disk()
        # exit()
    
    def save_qtree_correction(self, qtree_data, task_id, design_name=None, prompt=None, testbench=None, generated_sva=None, previous_metrics=None, final_metrics=None):
        """Save a qtree that led to functionality correction"""
        qtree_entry = {
            'qtree_data': qtree_data,
            'task_id': task_id,
            'design_name': design_name,
            'prompt': prompt,
            'testbench': testbench,  # Add testbench at top level
            'previous_metrics': previous_metrics,
            'final_metrics': final_metrics,
            'generated_sva': generated_sva
        }
        self.qtree_corrections.append(qtree_entry)
    
    def dump_qtree_corrections_to_disk(self):
        """Save all qtree corrections to disk (similar to suggestions)"""
        # Save as pickle file (like suggestions.pkl)
        pkl_filename = os.path.join(self.logdir, "qtrees.pkl")
        with open(pkl_filename, "wb") as pkl_file:
            pickle.dump(self.qtree_corrections, pkl_file)
        
        # Also save as JSON for human readability
        json_filename = os.path.join(self.logdir, "qtrees.json")
        with open(json_filename, 'w') as f:
            json.dump(self.qtree_corrections, f, indent=2)
        
        self.log_info(f'Saved {len(self.qtree_corrections)} qtrees to {pkl_filename}')
    
    def dump_qtrees_only(self):
        """Save only qtrees to disk without touching suggestions"""
        if self.qtree_corrections:
            self.dump_qtree_corrections_to_disk()
    
    @staticmethod
    def load_qtree_corrections(logdir):
        """Load qtree corrections from saved file (similar to loading suggestions)"""
        # Try JSON first (preferred for easier editing and debugging)
        json_filename = os.path.join(logdir, "qtrees.json")
        if os.path.exists(json_filename):
            with open(json_filename, 'r') as f:
                return json.load(f)
        
        # Try pickle if JSON doesn't exist (fallback for backward compatibility)
        pkl_filename = os.path.join(logdir, "qtrees.pkl")
        if os.path.exists(pkl_filename):
            with open(pkl_filename, 'rb') as pkl_file:
                return pickle.load(pkl_file)
        
        return []
    
    @staticmethod
    def retrieve_qtree_by_task(logdir, task_id, design_name=None):
        """Retrieve all qtrees for a specific task_id and optionally design_name"""
        qtree_list = Saver.load_qtree_corrections(logdir)
        
        if not qtree_list:
            return []
        
        # Filter by task_id
        results = [entry for entry in qtree_list if entry.get('task_id') == task_id]
        
        # Further filter by design_name if provided
        if design_name is not None:
            results = [entry for entry in results if entry.get('design_name') == design_name]
        
        return results
    
    @staticmethod
    def retrieve_qtree_by_combined_key(logdir, combined_key):
        """
        Retrieve qtrees using a combined key format: 'design_name_task_id' or just 'task_id'
        This provides backward compatibility while supporting the new unique key format
        """
        qtree_list = Saver.load_qtree_corrections(logdir)
        
        if not qtree_list:
            return []
        
        # Try to parse the combined key
        if '_' in combined_key:
            # Assume format is design_name_task_id
            # But be careful as task_id itself might contain underscores
            # For now, we'll search for matches in both ways
            results = []
            
            # First try exact match on task_id
            results.extend([entry for entry in qtree_list if entry.get('task_id') == combined_key])
            
            # Then try splitting and matching both fields
            for entry in qtree_list:
                task_id = entry.get('task_id', '')
                design_name = entry.get('design_name', '')
                if design_name and task_id and f"{design_name}_{task_id}" == combined_key:
                    if entry not in results:
                        results.append(entry)
            
            return results
        else:
            # Simple task_id lookup
            return [entry for entry in qtree_list if entry.get('task_id') == combined_key]
    
    @staticmethod
    def retrieve_qtree_by_prompt(logdir, prompt_keyword):
        """
        Retrieve qtrees by searching for keywords in the prompt field.
        Useful for finding similar assertion patterns.
        """
        qtree_list = Saver.load_qtree_corrections(logdir)
        
        if not qtree_list:
            return []
        
        results = []
        prompt_keyword_lower = prompt_keyword.lower()
        
        for entry in qtree_list:
            prompt = entry.get('prompt', '')
            if prompt and prompt_keyword_lower in prompt.lower():
                results.append(entry)
        
        return results
    
    @staticmethod
    def get_qtree_summary(logdir):
        """
        Get a summary of all saved qtrees including unique task_ids, design_names, and metrics improvements.
        """
        qtree_list = Saver.load_qtree_corrections(logdir)
        
        if not qtree_list:
            return {
                'total_qtrees': 0,
                'unique_task_ids': 0,
                'unique_designs': 0,
                'metrics_improvements': []
            }
        
        unique_task_ids = set()
        unique_designs = set()
        metrics_improvements = []
        
        for entry in qtree_list:
            task_id = entry.get('task_id')
            design_name = entry.get('design_name')
            previous_metrics = entry.get('previous_metrics', {})
            final_metrics = entry.get('final_metrics', {})
            
            if task_id:
                unique_task_ids.add(task_id)
            if design_name:
                unique_designs.add(design_name)
            
            # Calculate improvement
            if previous_metrics and final_metrics:
                improvement = {
                    'task_id': task_id,
                    'design_name': design_name,
                    'bleu_improvement': final_metrics.get('bleu', 0) - previous_metrics.get('bleu', 0),
                    'pec_improvement': final_metrics.get('pec', 0) - previous_metrics.get('pec', 0),
                    'relax_pec_improvement': final_metrics.get('relax_pec', 0) - previous_metrics.get('relax_pec', 0)
                }
                metrics_improvements.append(improvement)
        
        return {
            'total_qtrees': len(qtree_list),
            'unique_task_ids': len(unique_task_ids),
            'unique_designs': len(unique_designs),
            'metrics_improvements': metrics_improvements
        }

    def save_training_trace(self, trace):
        """Append one case's full self-learning trajectory as JSONL."""
        trace_path = join(self.logdir, "training_traces.jsonl")
        with open(trace_path, "a", encoding="utf-8") as trace_file:
            json.dump(trace, trace_file, ensure_ascii=False)
            trace_file.write("\n")

    def save_stats(self, stat_name, value):
        self.stats[stat_name].append(value)

    # def save_stats(self, stat_name, value):
    #     try:
    #         value = float(value)  # Ensure the value is numerical
    #     except ValueError:
    #         print(f"Cannot convert {value} to float. Skipping this stat.")
    #         return
    #     if stat_name not in self.stats:
    #         self.stats[stat_name] = []
    #     self.stats[stat_name].append(value)

    def print_stats(self):
        for stat_name, li in self.stats.items():
            print_stats(li, stat_name, saver=self)
    
    def track_suggestion_usage(self, task_id, used_suggestions, is_solved):
        """
        Track whether a case used suggestions and whether it was solved.
        
        Args:
            task_id: Identifier for the test case
            used_suggestions: Boolean indicating whether additional suggestions were used
            is_solved: Boolean indicating whether the problem was solved (pec == 1.0 or relax_pec == 1.0)
        """
        if used_suggestions:
            self.suggestion_tracking['with_suggestions'].append(task_id)
            if is_solved:
                self.suggestion_tracking['with_suggestions_solved'].append(task_id)
                self.save_stats('with_suggestions_solved', 1)
            else:
                self.save_stats('with_suggestions_solved', 0)
        else:
            self.suggestion_tracking['without_suggestions'].append(task_id)
            if is_solved:
                self.suggestion_tracking['without_suggestions_solved'].append(task_id)
                self.save_stats('without_suggestions_solved', 1)
            else:
                self.save_stats('without_suggestions_solved', 0)
    
    def print_suggestion_statistics(self):
        """
        Print comprehensive statistics about suggestion usage and problem solving.
        """
        print("\n" + "="*80)
        print("SUGGESTION USAGE AND SOLVING STATISTICS")
        print("="*80)
        
        # Count cases
        num_with_sugg = len(self.suggestion_tracking['with_suggestions'])
        num_without_sugg = len(self.suggestion_tracking['without_suggestions'])
        num_with_sugg_solved = len(self.suggestion_tracking['with_suggestions_solved'])
        num_without_sugg_solved = len(self.suggestion_tracking['without_suggestions_solved'])
        
        total_cases = num_with_sugg + num_without_sugg
        
        # Print summary
        print(f"\nTotal Cases: {total_cases}")
        print(f"\nCases WITH additional suggestions: {num_with_sugg}")
        print(f"  - Solved: {num_with_sugg_solved}")
        if num_with_sugg > 0:
            print(f"  - Solve rate: {num_with_sugg_solved/num_with_sugg*100:.2f}%")
        else:
            print(f"  - Solve rate: N/A (no cases with suggestions)")
        
        print(f"\nCases WITHOUT additional suggestions: {num_without_sugg}")
        print(f"  - Solved: {num_without_sugg_solved}")
        if num_without_sugg > 0:
            print(f"  - Solve rate: {num_without_sugg_solved/num_without_sugg*100:.2f}%")
        else:
            print(f"  - Solve rate: N/A (no cases without suggestions)")
        
        # Statistical comparison
        if num_with_sugg > 0 and num_without_sugg > 0:
            with_rate = num_with_sugg_solved/num_with_sugg*100
            without_rate = num_without_sugg_solved/num_without_sugg*100
            improvement = with_rate - without_rate
            print(f"\n" + "-"*80)
            print(f"Improvement with suggestions: {improvement:+.2f} percentage points")
            print("-"*80)
        
        # Save to JSON
        stats_dict = {
            'total_cases': total_cases,
            'with_suggestions': {
                'count': num_with_sugg,
                'solved': num_with_sugg_solved,
                'solve_rate': num_with_sugg_solved/num_with_sugg if num_with_sugg > 0 else 0
            },
            'without_suggestions': {
                'count': num_without_sugg,
                'solved': num_without_sugg_solved,
                'solve_rate': num_without_sugg_solved/num_without_sugg if num_without_sugg > 0 else 0
            }
        }
        
        # Also log to file
        self.log_dict_to_json(stats_dict, 'suggestion_usage_stats.json')
        self.log_info("\n" + "="*80)
        self.log_info("SUGGESTION USAGE STATISTICS")
        self.log_info("="*80)
        self.log_info(f"Total Cases: {total_cases}")
        self.log_info(f"Cases WITH suggestions: {num_with_sugg} (Solved: {num_with_sugg_solved})")
        self.log_info(f"Cases WITHOUT suggestions: {num_without_sugg} (Solved: {num_without_sugg_solved})")
        
        print("="*80 + "\n")
        
        return stats_dict


class NoOpContextManager:
    """A no-operation context manager that does nothing."""

    def __enter__(self):
        return None

    def __exit__(self, exc_type, exc_val, exc_tb):
        return False


saver = Saver()  # can be used by `from saver import saver`