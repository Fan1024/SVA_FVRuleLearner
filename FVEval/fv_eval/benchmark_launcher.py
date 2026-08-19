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
from dataclasses import asdict
import os
import time
import random
import requests

import httpx
import requests
import json

from saver import saver

print = saver.log_info
from config import FLAGS

import openai
import pickle
from pathlib import Path

# def get_api_key():
#     client_id = "nvssa-prd-CeZ-dDlSF4umKMgJnCqfGhpg4ZC8-G1LJk4X1lO8ofk"
#     client_secret = "ssap-6OreZfyoWyo4FWzAqOk"
#     url = 'https://prod.api.nvidia.com/oauth/api/v1/ssa/default/token'
#     headers = {'Content-Type': 'application/json'}
#     data = {
#         "client_id": client_id,
#         "client_secret": client_secret,
#         "scope": "azureopenai-readwrite",
#         "grant_type": "client_credentials",
#     }

#     response = requests.post(url, headers=headers, json=data)

#     if response.status_code == 200:
#         api_key = response.json().get('access_token')
#         return api_key
#     else:
#         raise Exception(
#             f"Failed to get API key: {response.status_code} - {response.text}"
#         )


# api_key = get_api_key()
# print("api_key: ", api_key)

# os.environ["AZURE_OPENAI_API_KEY"] = get_api_key()
# os.environ["AZURE_OPENAI_API_BASE"] = "https://prod.api.nvidia.com/llm/v1/azure/"
# import autogen
# endpoint_list = autogen.config_list_openai_aoai()
# endpoint_list[0]["model"] = "gpt-4o"

# exit()


# openai.api_key = "eyJraWQiOiI3MjAzZGFhMC1mNDc3LTQ1MjAtYjQ2ZC1lYTY5NjdiZTYyYmUiLCJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJudnNzYS1wcmQtQ2VaLWREbFNGNHVtS01nSm5DcWZHaHBnNFpDOC1HMUxKazRYMWxPOG9mayIsImF1ZCI6WyJudnNzYS1wcmQtQ2VaLWREbFNGNHVtS01nSm5DcWZHaHBnNFpDOC1HMUxKazRYMWxPOG9mayIsInM6NWtiZnhnYXFjM3hnejhuaGlkMXgxcjhjZmVzdG95cG4tdHJvZnV1bS1vYyJdLCJhenAiOiJudnNzYS1wcmQtQ2VaLWREbFNGNHVtS01nSm5DcWZHaHBnNFpDOC1HMUxKazRYMWxPOG9mayIsInNlcnZpY2UiOnsibmFtZSI6ImNoaXBOZU1vIiwiaWQiOiI1NHljanB4cjB1bXRwY2Z3LWN2Zm5ubGl0eHMxbmFqejRrZmk0MW5wdTlxIn0sImlzcyI6Imh0dHBzOi8vNWtiZnhnYXFjM3hnejhuaGlkMXgxcjhjZmVzdG95cG4tdHJvZnV1bS1vYy5zc2EubnZpZGlhLmNvbSIsInNjb3BlcyI6WyJhenVyZW9wZW5haS1yZWFkd3JpdGUiXSwiZXhwIjoxNzE4NzM2MDkzLCJ0b2tlbl90eXBlIjoic2VydmljZV9hY2NvdW50IiwiaWF0IjoxNzE4NzMyNDkzLCJqdGkiOiJlMGUxYzIxNC05MjliLTQzNjgtYTZjNy1lNDk2ZTkwNzU4M2MifQ.XxChwNXTnPvSxXdEEP9OrmAbN4S1Vi7Qy55RhV55ZtgMXNm-JfYF6ZE0dJTtiuUtoGmMsK_fYkBA4TYL0QkOfg"  # Set the api_key attribute to None
# # Set the client credentials
# openai.client_id = "nvssa-prd-CeZ-dDlSF4umKMgJnCqfGhpg4ZC8-G1LJk4X1lO8ofk"
# openai.client_secret = "ssap-6OreZfyoWyo4FWzAqOk"

# os.environ['OPENAI_API_KEY'] = (
#     "eyJraWQiOiI3MjAzZGFhMC1mNDc3LTQ1MjAtYjQ2ZC1lYTY5NjdiZTYyYmUiLCJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJudnNzYS1wcmQtQ2VaLWREbFNGNHVtS01nSm5DcWZHaHBnNFpDOC1HMUxKazRYMWxPOG9mayIsImF1ZCI6WyJudnNzYS1wcmQtQ2VaLWREbFNGNHVtS01nSm5DcWZHaHBnNFpDOC1HMUxKazRYMWxPOG9mayIsInM6NWtiZnhnYXFjM3hnejhuaGlkMXgxcjhjZmVzdG95cG4tdHJvZnV1bS1vYyJdLCJhenAiOiJudnNzYS1wcmQtQ2VaLWREbFNGNHVtS01nSm5DcWZHaHBnNFpDOC1HMUxKazRYMWxPOG9mayIsInNlcnZpY2UiOnsibmFtZSI6ImNoaXBOZU1vIiwiaWQiOiI1NHljanB4cjB1bXRwY2Z3LWN2Zm5ubGl0eHMxbmFqejRrZmk0MW5wdTlxIn0sImlzcyI6Imh0dHBzOi8vNWtiZnhnYXFjM3hnejhuaGlkMXgxcjhjZmVzdG95cG4tdHJvZnV1bS1vYy5zc2EubnZpZGlhLmNvbSIsInNjb3BlcyI6WyJhenVyZW9wZW5haS1yZWFkd3JpdGUiXSwiZXhwIjoxNzE4NzM2MDkzLCJ0b2tlbl90eXBlIjoic2VydmljZV9hY2NvdW50IiwiaWF0IjoxNzE4NzMyNDkzLCJqdGkiOiJlMGUxYzIxNC05MjliLTQzNjgtYTZjNy1lNDk2ZTkwNzU4M2MifQ.XxChwNXTnPvSxXdEEP9OrmAbN4S1Vi7Qy55RhV55ZtgMXNm-JfYF6ZE0dJTtiuUtoGmMsK_fYkBA4TYL0QkOfg"
# )

from langchain.schema import HumanMessage
from langchain.callbacks.streaming_stdout import StreamingStdOutCallbackHandler

from together import Together
from anthropic import Anthropic
import pandas as pd
from tqdm import tqdm

from FVEval.fv_eval import (
    prompts_nl2sva_machine,
    prompts_nl2sva_human,
    utils,
)
from FVEval.fv_eval.data import InputData, LMResult

"""
Base Class to Launch LLM Inference on Tasks in FVEval
"""


class BenchmarkLauncher(object):
    def __init__(
        self,
        save_dir: str,
        dataset_path: str,
        task: str = "nl2sva_human",
        model_name_list: list[str] = ["gpt-4"],
        num_icl_examples: int = 3,
        debug: bool = False,
        FVProcessor=None,
    ):
        self.FVProcessor = FVProcessor
        self.save_dir = save_dir
        self.dataset_path = dataset_path
        df = pd.read_csv(dataset_path)
        self.dataset = [InputData(**row) for _, row in df.iterrows()]
        # convert dataset into list of InputData

        # self.chat_client = openai.OpenAI(
        #     api_key="eyJraWQiOiI3MjAzZGFhMC1mNDc3LTQ1MjAtYjQ2ZC1lYTY5NjdiZTYyYmUiLCJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJudnNzYS1wcmQtQ2VaLWREbFNGNHVtS01nSm5DcWZHaHBnNFpDOC1HMUxKazRYMWxPOG9mayIsImF1ZCI6WyJudnNzYS1wcmQtQ2VaLWREbFNGNHVtS01nSm5DcWZHaHBnNFpDOC1HMUxKazRYMWxPOG9mayIsInM6NWtiZnhnYXFjM3hnejhuaGlkMXgxcjhjZmVzdG95cG4tdHJvZnV1bS1vYyJdLCJhenAiOiJudnNzYS1wcmQtQ2VaLWREbFNGNHVtS01nSm5DcWZHaHBnNFpDOC1HMUxKazRYMWxPOG9mayIsInNlcnZpY2UiOnsibmFtZSI6ImNoaXBOZU1vIiwiaWQiOiI1NHljanB4cjB1bXRwY2Z3LWN2Zm5ubGl0eHMxbmFqejRrZmk0MW5wdTlxIn0sImlzcyI6Imh0dHBzOi8vNWtiZnhnYXFjM3hnejhuaGlkMXgxcjhjZmVzdG95cG4tdHJvZnV1bS1vYy5zc2EubnZpZGlhLmNvbSIsInNjb3BlcyI6WyJhenVyZW9wZW5haS1yZWFkd3JpdGUiXSwiZXhwIjoxNzE4NzM0MzM4LCJ0b2tlbl90eXBlIjoic2VydmljZV9hY2NvdW50IiwiaWF0IjoxNzE4NzMwNzM4LCJqdGkiOiI0NjQzNzFjMy01ODRjLTQzZmItYmNiZS00MmYwYmI5YTVkM2QifQ.o14zh1Hd-82524A7hiFpsU9zufR45U3zC13otftWvDLa92CIEfJPCGK8vYpZD2pOUowZn0swQel0xB71PXFD_A"
        # )
        
        self.task = task
        self.model_api_list = self._prepare_models(model_name_list)
        self.num_icl_examples = num_icl_examples
        self.debug = debug
        self.experiment_id = dataset_path.split(".csv")[0].split("/")[-1]


    def get_data_list(self , subset):
        if FLAGS.all_examples:
            return list(self._build_iterator(model_name = 'N/A', subset = "all"))
        else:
            if FLAGS.src_examples[0] == FLAGS.task:
                return list(self._build_iterator(model_name = 'N/A', subset = subset))
            else:
                # return list(self._build_iterator(model_name = 'N/A', subset = "all"))
                # Lily1014: only use train examples
                return list(self._build_iterator(model_name = 'N/A', subset = subset))

    # def _build_iterator(self, model_name: str):
    #     if self.debug:
    #         # if debug, only take first 5 rows
    #         iterator = self.dataset[:2]
    #     else:
    #         iterator = tqdm(
    #             self.dataset,
    #             total=len(self.dataset),
    #             desc=f"Running for {model_name}",
    #         )
    #     return iterator

    # def _build_iterator(self, model_name: str):
    #     random.seed(FLAGS.random_seed)  # Set the random seed

    #     if self.debug:
    #         # if debug, only take 20 random rows
    #         if hasattr(FLAGS, 'only_test_ids'):
    #             random_indices = list(range(len(self.dataset)))
    #             random.shuffle(random_indices)
    #             iterator = [
    #                 self.dataset[random_indices[i]] for i in FLAGS.only_test_ids
    #             ]
    #         elif FLAGS.random_sample_size == -1:
    #             iterator = self.dataset[:2]
    #         else:
    #             random_indices = list(range(len(self.dataset)))
    #             random.shuffle(random_indices)
    #             iterator = [
    #                 self.dataset[i] for i in random_indices[: FLAGS.random_sample_size]
    #             ]
    #     else:
    #         # Create a random iterator for the entire dataset
    #         if FLAGS.random_sample_size == -1:
    #             iterator = tqdm(
    #                 self.dataset,
    #                 total=len(self.dataset),
    #                 desc=f"Running for {model_name}",
    #             )
    #         else:
    #             iterator = random.sample(self.dataset, len(self.dataset))
    #             iterator = tqdm(
    #                 iterator,
    #                 total=len(iterator),
    #                 desc=f"Running for {model_name}",
    #             )
    #     return iterator

    def _build_iterator(self, model_name: str, subset: str = FLAGS.global_task):
        # TextGrad: built under 'train'
        random.seed(FLAGS.random_seed)  # Set the random seed

        total_samples = len(self.dataset)
        shuffled_indices = list(range(total_samples))
        random.shuffle(shuffled_indices)

        # Split the dataset into train and test subsets
        test_size = int(total_samples * FLAGS.split_ratios['test'])
        train_size = int(total_samples * FLAGS.split_ratios['train'])

        test_indices = shuffled_indices[:test_size]
        train_indices = shuffled_indices[test_size:(test_size + train_size+1)]

        # Ensure num_group and group_id are integers
        num_group = int(FLAGS.num_group)
        group_id = int(FLAGS.group_id)

        # Helper function to split indices based on group_id and num_group
        def split_indices(indices, group_id, num_group):
            group_size = len(indices) // num_group
            remainder = len(indices) % num_group
            
            start = group_id * group_size + min(group_id, remainder)
            end = start + group_size + (1 if group_id < remainder else 0)
            
            return indices[start:end]

        # Adjust split_indices to account for start_temp within each group's subset
        def apply_start_temp(indices, start_temp):
            return indices[start_temp:]

        # Calculate the maximum valid group_id for training and testing sets
        max_train_group_id = num_group - 1
        max_test_group_id = num_group - 1

        # Assertions to ensure group_id is valid for training and testing sets
        if subset == 'train':
            assert 0 <= group_id <= max_train_group_id, (
                f"Invalid group_id for training dataset. "
                f"group_id: {group_id}, num_group: {num_group}, "
                f"train_size: {len(train_indices)}. "
                f"Valid group_id range: 0 to {max_train_group_id}."
            )
            # Print the sizes of the overall training and testing subsets

        elif subset == 'inference':
            assert 0 <= group_id <= max_test_group_id, (
                f"Invalid group_id for testing dataset. "
                f"group_id: {group_id}, num_group: {num_group}, "
                f"test_size: {len(test_indices)}. "
                f"Valid group_id range: 0 to {max_test_group_id}."
            )        

        if subset == 'examples':
            split_indices = train_indices  # Use all training indices for examples
            print(f"Overall example size: {len(split_indices)}")
            print(f"Train IDs:{split_indices}")
        elif subset == 'train':
            split_indices = split_indices(train_indices, group_id, num_group)
            split_indices = apply_start_temp(split_indices, FLAGS.start_num)
            print(f"Overall training subset size: {len(split_indices)}")
            print(f"Train IDs:{split_indices}")
        elif subset == 'inference':
            split_indices = split_indices(test_indices, group_id, num_group)
            split_indices = apply_start_temp(split_indices, FLAGS.start_num)
            print(f"Overall testing subset size: {len(split_indices)}")
            print(f"Test IDs:{split_indices}")
        elif subset == "all":
            split_indices = train_indices + test_indices
            print(f"Overall subset size: {len(split_indices)}")
            print(f"All IDs:{split_indices}")
        else:
            raise ValueError(f"Unknown global task: {subset}")

        # Print the sizes of the group's training and testing subsets
        if subset != 'examples':  # No group splitting for examples
            print(f"Group ID: {group_id}")
            print(f"Num Groups: {num_group}")
            print(f"Group subset size: {len(split_indices)}")

        if self.debug:
            if hasattr(FLAGS, 'only_test_ids'):
                iterator = [self.dataset[i] for i in FLAGS.only_test_ids]
                # breakpoint()
            elif FLAGS.random_sample_size == -1:
                iterator = self.dataset[:2]
            else:
                # Split on FLAGS.random_sample_size in debug mode
                sample_size = min(FLAGS.random_sample_size, len(split_indices))
                sampled_indices = random.sample(split_indices, sample_size)
                iterator = [self.dataset[i] for i in sampled_indices]
            # print(f"@@@Debugging dataset size: {len(iterator)}")
        else:
            if FLAGS.random_sample_size == -1:
                iterator = [self.dataset[i] for i in split_indices]
            else:
                sample_size = min(FLAGS.random_sample_size, len(split_indices))
                sampled_indices = random.sample(split_indices, sample_size)
                iterator = [self.dataset[i] for i in sampled_indices]

        desc = f"Running for {model_name} ({FLAGS.global_task} set"
        if hasattr(FLAGS, 'RAG_content'):
            desc += f", RAG: {FLAGS.RAG_content}"
        desc += ")"
        # Wrap with tqdm for progress tracking
        iterator = tqdm(
            iterator,
            total=len(iterator),
            desc=desc,
        )

        return iterator


    def generate_system_prompt(self):
        raise NotImplementedError("generate_system_prompt not implemented")

    def generate_question_prompt(sefl, row: InputData):
        pass

    def generate_user_prompt_prefix(self, row: InputData):
        raise NotImplementedError("generate_user_prompt_prefix not implemented")

    def package_testbench(self, row: InputData, lm_response: str):
        raise NotImplementedError("package_testbench not implemented")

    def get_cot_strategy(self, cot_strategy: str) -> list[tuple[str, str]]:
        return []

    def _prepare_models(self, model_name_list: str):
        TOGETHER_MODEL_DICT = {
            "llama-3-8b": "meta-llama/Llama-3-8b-chat-hf",
            "llama-3-70b": "meta-llama/Llama-3-70b-chat-hf",
            "codellama-34b": "codellama/CodeLlama-34b-Instruct-hf",
            "llama-2-70b": "meta-llama/Llama-2-70b-chat-hf",
            "mixtral-8x22b": "mistralai/Mixtral-8x22B-Instruct-v0.1",
            "mixtral-8x7b": "mistralai/Mixtral-8x7B-Instruct-v0.1",
        }
        model_api_list = []
        for model_name in model_name_list:
            if "vllm" in model_name:
                api_provider = "vllm"
                api_key = "EMPTY"
                base_url = "http://localhost:8000/v1"
                full_model_name = (
                    openai.OpenAI(
                        api_key=api_key,
                        base_url=base_url,
                    )
                    .models.list()
                    .data[0]
                    .id
                )
            elif model_name in TOGETHER_MODEL_DICT:
                api_provider = "together"
                api_key = os.getenv("TOGETHER_API_KEY")
                base_url = "https://api.together.xyz/v1"
                full_model_name = TOGETHER_MODEL_DICT[model_name]
            elif "claude" in model_name:
                api_provider = "anthropic"
                api_key = os.getenv("ANTHROPIC_API_KEY")
                base_url = "https://api.anthropic.com/v1"
                if "opus" in model_name:
                    full_model_name = "claude-3-opus-20240229"
                elif "sonnet" in model_name:
                    full_model_name = "claude-3-sonnet-20240229"
                elif "haiku" in model_name:
                    full_model_name = "claude-3-haiku-20240229"
                else:
                    raise ValueError(f"Unknown Anthropic model: {model_name}")
            elif "gpt" in model_name:
                api_provider = "openai"
                api_key = os.getenv("OPENAI_API_KEY")
                base_url = "https://api.openai.com/v1"
                if "gpt-4-turbo" in model_name:
                    # full_model_name = "gpt-4-0125-preview"
                    full_model_name = "gpt-4-turbo-2024-04-09"
                elif model_name == "gpt-4o-2024-11-20":
                    full_model_name = "gpt-4o-2024-11-20"
                elif model_name == "gpt-4o":
                    full_model_name = "gpt-4o"
                elif model_name == "gpt-4":
                    full_model_name = "gpt-4-0613"
                elif "gpt-3.5-turbo" in model_name:
                    full_model_name = "gpt-3.5-turbo-0125"
                    full_model_name = model_name
                else:
                    raise ValueError(f"Unknown OpenAI model: {model_name}")
            elif "o" in model_name:
                api_provider = "openai"
                api_key = os.getenv("OPENAI_API_KEY")
                base_url = "https://api.openai.com/v1"
                if model_name == "o1-20241217":
                    full_model_name = "o1-20241217"
                elif model_name == "o3-mini-20250131":
                    full_model_name = "o3-mini-20250131"
            elif "llama" in model_name:
                api_provider = "openai"
                api_key = FLAGS.api_key
                base_url = FLAGS.base_url
                if model_name == "meta/llama3-70b-instruct":
                    full_model_name = "llama3-70b-instruct"
                elif model_name == "meta/llama3-8b-instruct":
                    full_model_name = "llama3-8b-instruct"
                else:
                    raise ValueError(f"Unknown Meta model: {model_name}")
            elif "mixtral" in model_name:
                api_provider = "openai"
                api_key = FLAGS.api_key
                base_url = FLAGS.base_url
                if model_name == "mistralai/mixtral-8x22b-instruct-v0.1":
                    full_model_name = "mixtral-8x22b-instruct-v0.1"
                elif model_name == "mixtral_8x7b":
                    full_model_name = "mixtral_8x7b"
                else:
                    raise ValueError(f"Unknown Mistralai model: {model_name}")
            else:
                raise ValueError(f"Unknown model: {model_name}")
            model_api_list.append(
                {
                    "short_model_name": model_name,
                    "model_name": full_model_name,
                    "api_provider": api_provider,
                    "api_key": api_key,
                    "base_url": base_url,
                }
            )
        return model_api_list

    def setup_chat_client(
        self,
        model_name: str,
        short_model_name: str,
        api_provider: str,
        api_key: str,
        base_url: str,
    ):

        if FLAGS.llm_mode == 'agent':
            pass
        elif FLAGS.llm_mode == 'baseline':

            if api_provider == "vllm" or api_provider == "openai":
                self.chat_client = openai.OpenAI(
                    api_key=api_key,
                    base_url=base_url,
                )
                self.api_provider = api_provider
            elif api_provider == "together":
                self.chat_client = Together(
                    api_key=api_key,
                    base_url=base_url,
                )
                self.api_provider = api_provider
            elif api_provider == "anthropic":
                self.chat_client = Anthropic(
                    api_key=api_key,
                    base_url=base_url,
                )
                self.api_provider = api_provider
            else:
                raise ValueError(f"Unknown API provider: {api_provider}")
        else:
            raise NotImplementedError()

    def run_lm(
        self,
        model_name,
        system_prompt,
        user_prompt,
        temperature: float = 0.0,
        max_tokens: int = 100,
        max_retries: int = 40,
        num_cases: int = 1,
        row=None
    ):
        
        def _handle_exception(delay, error, num_retries, e):
            # Sleep for the delay
            time.sleep(delay)
            # Increment the delay
            delay *= 2 * (1 + 1 * random.random())
            # Set the error to the last exception
            error = e
            # Increment retries
            num_retries += 1
    
            utils.print_error(
                "Retrying  after error",
                f" {e} (retry {num_retries} of {max_retries})",
            )
            return delay, error, num_retries


        num_retries = 0
        delay = 1.0
        error = None
        if temperature == 0.0:
            top_p = 1.0
        else:
            top_p = 0.95
        while num_retries <= 20:
            try:
                if FLAGS.llm_mode == 'agent' and FLAGS.LLM_gateaway != "Finetune":

                    return [
                        self.FVProcessor.call_agent_get_response(
                            system_prompt, user_prompt, row
                        )
                    ]

                elif FLAGS.LLM_gateaway == "Finetune":
                    pass
                    # Lily TODO: Implement Mixtral-Finetune

                elif FLAGS.llm_mode == 'baseline':
                    api_provider = self.api_provider

                    if (
                        api_provider == "vllm"
                        or api_provider == "together"
                        or api_provider == "openai"
                    ):
                        completion = self.chat_client.chat.completions.create(
                            model=model_name,
                            messages=[
                                {"role": "system", "content": system_prompt},
                                {"role": "user", "content": user_prompt},
                            ],
                            max_tokens=max_tokens,
                            temperature=temperature,
                            top_p=top_p,
                            n=num_cases,
                        )
                        return [choice.message.content for choice in completion.choices]
                    elif api_provider == "anthropic":
                        completion = Anthropic().messages.create(
                            model=model_name,
                            system=system_prompt,
                            messages=[
                                {"role": "user", "content": user_prompt},
                            ],
                            max_tokens=max_tokens,
                            temperature=temperature,
                        )
                        time.sleep(2)
                        return [textblock.text for textblock in completion.content]
                else:
                    raise NotImplementedError()
                
            except httpx.LocalProtocolError as e:
                delay, error, num_retries = _handle_exception(delay, error, num_retries, e)

            except openai._exceptions.APIConnectionError as e:
                delay, error, num_retries = _handle_exception(delay, error, num_retries, e)
            # Raise exceptions for any errors specified
            except Exception as e:
                delay, error, num_retries = _handle_exception(delay, error, num_retries, e)

            if error is not None:
                raise error
        return None

    def run_lm_chain(
        self,
        row: InputData,
        model_name: str,
        system_prompt: str,
        user_prompt: str,
        temperature: float = 0.0,
        max_tokens: int = 100,
        max_retries: int = 20,
        num_cases: int = 1,
    ):
        lm_response_list = self.run_lm(
            model_name=model_name,
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            temperature=temperature,
            max_tokens=max_tokens,
            max_retries=max_retries,
            num_cases=num_cases,
            row=row
        )

        if self.debug:
            debug_id = row.design_name + ("/" + row.task_id if row.task_id else "")
            utils.print_user_prompt(debug_id, user_prompt)
            utils.print_lm_response(model_name, lm_response_list[0])
        return lm_response_list

    def run_experiment_single_model(
        self,
        model_name: str,
        temperature: float = 0.0,
        max_tokens: int = 100,
        cot_question_chain: list[tuple[str, str]] = [],
        num_cases: int = 1,
    ):
        raise NotImplementedError("run_experiment_single_model not implemented")

    def run_benchmark(
        self,
        temperature: float = 0.0,
        max_tokens: int = 100,
        cot_strategy: str = "default",
        num_cases: int = 1,
    ):
        cot_question_chain = self.get_cot_strategy(cot_strategy)
        # print(f"cot_stategy = {cot_strategy}")
        for model_dict in self.model_api_list:
            self.setup_chat_client(**model_dict)
            results = self.run_experiment_single_model(
                model_dict["model_name"],
                temperature=temperature,
                max_tokens=max_tokens,
                cot_question_chain=cot_question_chain,
                num_cases=num_cases,
            )
            # print(f"@@@DEBUG: results = {results}")

            self.save_results(model_dict["short_model_name"], results)
        return results

    def save_results(self, model_name: str, results: list[LMResult]):
        model_name = model_name.split("/")[-1].replace(" ", "_")
        results_df = pd.DataFrame([asdict(response) for response in results])
        results_df.to_csv(
            os.path.join(self.save_dir, f"{model_name}_{self.experiment_id}.csv"),
            index=False,
        )


"""
LLM Inference Launcher Specific to NL2SVA Benchmark Tasks
- Launcher classes for NL2SVA-Human and NL2SVA-Machine inherit this class
"""


class NL2SVALauncher(BenchmarkLauncher):
    def __init__(
        self,
        save_dir: str,
        dataset_path: str,
        task: str = "nl2sva_human",
        model_name_list: list[str] = ["gpt-4"],
        num_icl_examples: int = 3,
        debug: bool = False,
        FVProcessor=None,
    ):
        super().__init__(
            save_dir,
            dataset_path,
            task,
            model_name_list,
            num_icl_examples,
            debug,
            FVProcessor,
        )

    def package_testbench(self, row: InputData, lm_response: str):
        question_prompt = self.generate_question_prompt(row)
        reference_assertion_text = row.ref_solution.replace("asrt", "reference")

        # print(f"@@@DEBUG: lm_response {lm_response}")
        assertion_text = utils.parse_code_response(lm_response)

        # retrieve question text
        commented_question_text = "\n//".join(question_prompt.split("\n"))
        testbench_text = row.testbench
        packaged_tb_text = (
            testbench_text.split("endmodule")[0]
            + "\n\n"
            + commented_question_text
            + "\n\n"
            + reference_assertion_text
            + "\n\n"
            + assertion_text
            + "\n\n"
            + "endmodule"
        )
        return packaged_tb_text

    def run_experiment_single_model(
        self,
        model_name: str,
        temperature: float = 0.0,
        max_tokens: int = 100,
        cot_question_chain: list[tuple[str, str]] = [],
        num_cases: int = 1,
    ):
        results = []
        system_prompt = self.generate_system_prompt()
        for row in self._build_iterator(model_name):
            user_prompt = self.generate_user_prompt_prefix(row)
            if not cot_question_chain:
                user_prompt += "\n" + self.generate_question_prompt(row)
            else:
                raise NotImplementedError("COT question chain not implemented")

            # Save outside
            # if FLAGS.task == "nl2sva_human" or FLAGS.task == "nl2sva_machine":
            data = {
                'experiment_id': self.experiment_id,
                'task_id': row.design_name + ("_" + row.task_id) if row.task_id else row.design_name,
                'model_name': model_name,
                'ref_solution': row.ref_solution,
                'user_prompt': user_prompt,
                'testbench': (row.testbench) if row.testbench else "\n",
                'design_rtl': "\n",
                'cot_response': "\n",
            }

            file_path = Path(saver.logdir) / 'var_temp.pkl'
            
            # Clean up any existing file to avoid data pollution between cases
            if file_path.exists():
                file_path.unlink()  # Delete the old file

            # elif FLAGS.task == "nl2sva_opencore":
            #     data = {
            #         'experiment_id': self.experiment_id,
            #         'task_id': row.design_name + ("_" + row.task_id) if row.task_id else "\n",
            #         'model_name': model_name,
            #         'ref_solution': row.ref_solution,
            #         'user_prompt': user_prompt,
            #         'testbench': (row.testbench) if row.testbench else "\n",
            #         'design_rtl': "\n",
            #         'cot_response': "\n",
            #     }

            #     file_path = Path(saver.logdir) / 'var_temp.pkl'

            # Check if the file already exists
            # if FLAGS.use_JG == True:
            #     if file_path.exists():
            #         raise FileExistsError(f"The file {file_path} already exists.")

            # Save the dictionary using pickle
            with open(file_path, 'wb') as file:
                pickle.dump(data, file)

            lm_response_list = self.run_lm_chain(
                row=row,
                model_name=model_name,
                system_prompt=system_prompt,
                user_prompt=user_prompt,
                temperature=temperature,
                max_tokens=max_tokens,
                num_cases=num_cases,
            )

            for i, lm_response in enumerate(lm_response_list):
                if self.debug:
                    utils.print_lm_response("reference", row.ref_solution)
                    # print(f'@@@DEBUG: LLM response:{lm_response}')
                if self.task == "nl2sva_machine" or self.task == "nl2sva_human":
                    packaged_tb_text = self.package_testbench(row, lm_response)
                    response = LMResult(
                        experiment_id=self.experiment_id,
                        task_id=row.design_name + "_" + row.task_id + f"_trial_{i}",
                        model_name=model_name,
                        response=lm_response,
                        ref_solution=row.ref_solution,
                        user_prompt=user_prompt,
                        output_tb=packaged_tb_text,
                        design_rtl="\n",
                        cot_response="cot_response\n",
                    )
                    results.append(response)
                elif self.task == "nl2sva_opencore":
                    post_ref_solution = f"assert property({row.ref_solution});"
                    safe_design_name = row.design_name.replace('/', '_')
                    response = LMResult(
                        experiment_id=self.experiment_id,
                        task_id=safe_design_name + f"_trial_{i}",
                        model_name=model_name,
                        response=lm_response,
                        ref_solution=post_ref_solution,
                        user_prompt=user_prompt,
                        output_tb="\n",
                        design_rtl="\n",
                        cot_response="cot_response\n",
                    )
                    results.append(response)
                else:
                    raise NotImplementedError(f"Task '{self.task}' is not implemented")
        return results


"""
LLM Inference Launcher Specific to NL2SVA-Human
"""


class NL2SVAHumanLauncher(NL2SVALauncher):
    def __init__(
        self,
        save_dir: str,
        dataset_path: str,
        task: str = "nl2sva_human",
        model_name_list: list[str] = ["gpt-4"],
        num_icl_examples: int = 3,
        debug: bool = False,
        FVProcessor=None,
    ):
        super().__init__(
            save_dir,
            dataset_path,
            task,
            model_name_list,
            num_icl_examples,
            debug,
            FVProcessor,
        )

    def generate_system_prompt(self):
        return prompts_nl2sva_human.SVAGEN_HEADER

    def generate_question_prompt(self, row: InputData):
        question_prompt = prompts_nl2sva_human.SVAGEN_QUESTION_PREAMBLE
        question_prompt += row.prompt + "\n"
        return question_prompt + prompts_nl2sva_human.SVAGEN_QUESTION_POSTAMBLE

    def generate_user_prompt_prefix(self, row: InputData):
        if self.num_icl_examples == 0:
            user_prompt_prefix = ""
        elif self.num_icl_examples == 1:
            user_prompt_prefix = prompts_nl2sva_human.SVAGEN_HUMAN_ICL_EXAMPLE_1
        elif self.num_icl_examples == 3:
            user_prompt_prefix = prompts_nl2sva_human.SVAGEN_HUMAN_ICL_EXAMPLE_3
        else:
            utils.print_error(
                "ERROR",
                f"Unsupported number of in-context examples: {self.num_icl_examples}",
            )
        user_prompt_prefix += "\n\n" + prompts_nl2sva_human.SVAGEN_TB_PREAMBLE
        user_prompt_prefix += "\n" + row.testbench
        return user_prompt_prefix


"""
LLM Inference Launcher Specific to NL2SVA-Machine
"""


class NL2SVAMachineLauncher(NL2SVALauncher):
    def __init__(
        self,
        save_dir: str,
        dataset_path: str,
        task: str = "nl2sva_machine",
        model_name_list: list[str] = ["gpt-4"],
        num_icl_examples: int = 3,
        debug: bool = False,
        FVProcessor=None,
    ):
        super().__init__(
            save_dir,
            dataset_path,
            task,
            model_name_list,
            num_icl_examples,
            debug,
            FVProcessor,
        )

    def generate_system_prompt(self):
        return prompts_nl2sva_machine.SVAGEN_HEADER

    def generate_question_prompt(self, row: InputData):
        question_prompt = prompts_nl2sva_machine.SVAGEN_QUESTION_PREAMBLE
        question_prompt += row.prompt + "\n"

        if self.num_icl_examples == 0:
            return (
                question_prompt
                + prompts_nl2sva_machine.SVAGEN_QUESTION_POSTAMBLE_ZERO_SHOT
            )
        return question_prompt + prompts_nl2sva_machine.SVAGEN_QUESTION_POSTAMBLE

    def generate_user_prompt_prefix(self, row: InputData):
        user_prompt_prefix = ""
        if self.task == "nl2sva_opencore":
            user_prompt_prefix += prompts_nl2sva_machine.OPENCORE_SVAGEN_MODULE_PREAMBLE
            user_prompt_prefix += "\n" + row.module_interface + "\n\n"
        if self.num_icl_examples == 0:
            user_prompt_prefix += ""
        elif self.num_icl_examples == 1:
            user_prompt_prefix += prompts_nl2sva_machine.SVAGEN_MACHINE_ICL_EXAMPLE_1
        elif self.num_icl_examples == 2:
            user_prompt_prefix += prompts_nl2sva_machine.SVAGEN_MACHINE_ICL_EXAMPLE_2
        elif self.num_icl_examples == 3:
            user_prompt_prefix += prompts_nl2sva_machine.SVAGEN_MACHINE_ICL_EXAMPLE_3
        else:
            utils.print_error(
                "ERROR",
                f"unsupported number of in-context examples: {self.num_icl_examples}",
            )
        return user_prompt_prefix