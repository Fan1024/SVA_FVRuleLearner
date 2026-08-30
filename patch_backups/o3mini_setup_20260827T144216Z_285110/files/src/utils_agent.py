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
import time
import sqlite3
# from transformers import AutoTokenizer
from saver import saver
import re
import json
import httpx
import os
import copy
import shutil
from pathlib import Path
from FVEval.fv_eval import utils as utils2
from langchain.schema import HumanMessage
from langchain.callbacks.streaming_stdout import StreamingStdOutCallbackHandler
from openai import AzureOpenAI, OpenAI
from openai import APITimeoutError, APIError, APIConnectionError, InternalServerError
import anthropic
from tenacity import retry, retry_if_exception_type, wait_exponential, stop_after_attempt
from hardware_agent.basic_client import BasicClient

# Color codes for terminal output
CYAN = "\033[96m"
GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
RESET = "\033[0m"

print = saver.log_info
import tiktoken

class RateLimitError(Exception):
    pass


def is_direct_llm_gateway(gateway_name):
    return gateway_name in {"openai", "claude"}

def check_and_fix_cache(cache_dir=".cache"):
    """
    Check for corrupted cache databases and fix them by removing corrupted files.
    Returns True if any corrupted cache was found and fixed.
    """
    cache_path = Path(cache_dir)
    if not cache_path.exists():
        return False
    
    corrupted_found = False
    for cache_seed_dir in cache_path.iterdir():
        if cache_seed_dir.is_dir():
            cache_db = cache_seed_dir / "cache.db"
            if cache_db.exists():
                try:
                    # Try to open and validate the database
                    conn = sqlite3.connect(str(cache_db))
                    cursor = conn.cursor()
                    cursor.execute("PRAGMA integrity_check;")
                    result = cursor.fetchone()
                    conn.close()
                    
                    if result[0] != "ok":
                        print(f"{YELLOW}⚠️  Corrupted cache detected: {cache_db}{RESET}")
                        corrupted_found = True
                        # Backup and remove corrupted cache
                        backup_name = f"{cache_seed_dir.name}.corrupted.{int(time.time())}"
                        backup_path = cache_path / backup_name
                        shutil.move(str(cache_seed_dir), str(backup_path))
                        print(f"{GREEN}✓ Moved corrupted cache to: {backup_path}{RESET}")
                        
                except sqlite3.DatabaseError as e:
                    print(f"{YELLOW}⚠️  Database error in {cache_db}: {e}{RESET}")
                    corrupted_found = True
                    # Backup and remove corrupted cache
                    backup_name = f"{cache_seed_dir.name}.corrupted.{int(time.time())}"
                    backup_path = cache_path / backup_name
                    shutil.move(str(cache_seed_dir), str(backup_path))
                    print(f"{GREEN}✓ Moved corrupted cache to: {backup_path}{RESET}")
                    
                except Exception as e:
                    print(f"{YELLOW}⚠️  Unexpected error checking {cache_db}: {e}{RESET}")
    
    return corrupted_found

def is_o_series_model(model_name):
    """Check if the model is an o-series model (o1, o3, etc.)"""
    if not model_name:
        return False
    # Check for o1, o3 patterns at the start of the model name
    return bool(re.match(r'^o[134]-', model_name.lower()))

def get_tokenizer(llm_model):
    # tiktoken 0.7 does not know every o-series alias, but it includes the
    # o200k_base encoding used by o3-mini.
    if is_o_series_model(llm_model):
        return tiktoken.get_encoding("o200k_base")

    try:
        return tiktoken.encoding_for_model(llm_model)
    except KeyError as exc:
        print(
            f"Tokenizer mapping unavailable for {llm_model}: {exc}. "
            "Falling back to cl100k_base."
        )
        return tiktoken.get_encoding("cl100k_base")

def count_tokens(tokenizer, message):
    # Tokenize the message using tiktoken
    try:
        return len(tokenizer.encode(message))
    except Exception as e:
        print(f"Error tokenizing message: {e}")
        raise e


def convert_time_to_float(time_str):
    # Use regular expression to find the numeric part of the string
    match = re.search(r"(\d+\.\d+)", time_str)
    if match:
        return float(match.group(1))
    else:
        raise ValueError(f"Cannot convert {time_str} to float.")

# def initiate_chat_with_retry(agent_user, agent_coding, message, retries=FLAGS.GPT_retries, backoff_factor=FLAGS.backoff_factor, **kwargs):
#     agent_user.revalidate_llm_config()
#     agent_coding.revalidate_llm_config()
#     if not message:
#         message = kwargs.get('message')
    
#     if not message:
#         raise ValueError("Message must be provided either as a parameter or in kwargs.")
    
#     # Initialize statistics dictionary if not already done
#     if not hasattr(agent_user, 'stats'):
#         agent_user.stats = {'runtime': [], 'tokens': []}
    
#     # Get the tokenizer for the model
#     tokenizer = get_tokenizer(FLAGS.llm_model)
    
#     for attempt in range(retries):
#         start_time = time.time()
#         try:
#             # message = 'test the issue belongs to the message'
#             response = agent_user.initiate_chat(agent_coding, message=message)
#             LLM_runtime = time.time() - start_time

#             # print(f"@@@DEBUG: runtime = {type(runtime)} {runtime}")
#             tokens = count_tokens(tokenizer, message)
            
#             # Save stats
#             saver.save_stats('LLM_runtime', LLM_runtime)
#             saver.save_stats('tokens', tokens)
            
#             # Process response and return if successful
#             response_str = response.chat_history[-1]['content']
#             return response_str
        
#         except RateLimitError as e:
#             wait_time = backoff_factor ** attempt
#             print(f"@@@{FLAGS.llm_model}: Rate limit exceeded. Retrying in {wait_time} seconds...")
#             time.sleep(wait_time)
#         except Exception as e:
#             wait_time = backoff_factor ** attempt
#             print(f"@@@{FLAGS.llm_model}: An error occurred: {e}. Retrying in {wait_time} seconds...")
#             time.sleep(wait_time)

def initiate_chat_with_retry_legacy(agent_user, agent_coding, message, retries, backoff_factor = FLAGS.backoff_factor, **kwargs):
    """
    The original logic is preserved here. 
    This function is identical to your original initiate_chat_with_retry code.
    """
    agent_user.revalidate_llm_config()
    agent_coding.revalidate_llm_config()
    if not message:
        message = kwargs.get('message')
    
    if not message:
        raise ValueError("Message must be provided either as a parameter or in kwargs.")
    
    # Initialize statistics dictionary if not already done
    if not hasattr(agent_user, 'stats'):
        agent_user.stats = {'runtime': [], 'tokens': []}
    
    # Get the tokenizer for the model
    tokenizer = get_tokenizer(FLAGS.llm_model)
    
    cache_fix_attempted = False
    
    for attempt in range(retries):
        start_time = time.time()
        try:
            response = agent_user.initiate_chat(agent_coding, message=message)
            LLM_runtime = time.time() - start_time
            tokens = count_tokens(tokenizer, message)
            
            # Save stats
            saver.save_stats('LLM_runtime', LLM_runtime)
            saver.save_stats('tokens', tokens)
            
            # Process response and return if successful
            response_str = response.chat_history[-1]['content']
            return response_str
        
        # DEBUG
        except RateLimitError as e:
            wait_time = backoff_factor ** attempt
            print(f"@@@{FLAGS.llm_model}: Rate limit exceeded. Retrying in {wait_time} seconds...")
            time.sleep(wait_time)
        except sqlite3.DatabaseError as e:
            # Handle database corruption errors specifically
            if "database" in str(e).lower() and not cache_fix_attempted:
                print(f"{YELLOW}⚠️  Database error detected. Attempting to fix cache...{RESET}")
                check_and_fix_cache()
                cache_fix_attempted = True
                print(f"{GREEN}✓ Cache check complete. Retrying immediately...{RESET}")
                continue
            else:
                wait_time = backoff_factor ** attempt
                print(f"@@@{FLAGS.llm_model}: Database error: {e}. Retrying in {wait_time} seconds...")
                time.sleep(wait_time)
        except Exception as e:
            # Check if this is a database-related error in the exception message
            if "database" in str(e).lower() and not cache_fix_attempted:
                print(f"{YELLOW}⚠️  Database-related error detected: {e}. Attempting to fix cache...{RESET}")
                check_and_fix_cache()
                cache_fix_attempted = True
                print(f"{GREEN}✓ Cache check complete. Retrying immediately...{RESET}")
                continue
            else:
                wait_time = backoff_factor ** attempt
                print(f"@@@{FLAGS.llm_model}: An error occurred: {e}. Retrying in {wait_time} seconds...")
                time.sleep(wait_time)

    # If we reach this point, no successful response was obtained
    raise RuntimeError("Failed to get a response after all retries.")


def initiate_chat_with_retry(agent_user, agent_coding, message=None, retries=FLAGS.GPT_retries, backoff_factor=2,
                             model=None,
                             prepare_env_args={"SERVER_COOLNAME": "aromatic-partridge"},
                             temperature=0.0,
                             stop=["extra_id_1"],
                             callbacks=None,
                             streaming=True,
                             **kwargs):
    """
    A wrapper function that can either use the original legacy approach
    or a direct OpenAI-compatible gateway call.
    """
    
    if not message:
        message = kwargs.get('message')
    if not message:
        raise ValueError("Message must be provided either as a parameter or in kwargs.")

    # Determine which method to use
    use_direct_llm = hasattr(FLAGS, 'LLM_gateaway') and is_direct_llm_gateway(FLAGS.LLM_gateaway)
    # breakpoint()
    
    if use_direct_llm:
        
        # Try multiple locations where system message might be stored
        system_prompt = agent_coding.system_message
        
        # Determine which model to use
        # Priority: agent_model parameter > agent's model attribute > FLAGS.llm_model
        effective_model = model
        if effective_model is None and hasattr(agent_coding, 'llm_config') and isinstance(agent_coding.llm_config, dict):
            # Try to extract model from agent's llm_config
            config_list = agent_coding.llm_config.get('config_list', [])
            if config_list and isinstance(config_list[0], dict):
                effective_model = config_list[0].get('model')
        
        # Debug logging if enabled
        # if hasattr(FLAGS, 'debug') and FLAGS.debug and system_prompt:
        #     print(f"Extracted system prompt: {system_prompt[:100]}...")
        
        # Initialize statistics dictionary if not already done
        if not hasattr(agent_user, 'stats'):
            agent_user.stats = {'runtime': [], 'tokens': []}
        
        # Implement retry logic for the direct OpenAI gateway
        for attempt in range(retries):
            try:
                # Use llm_inference for direct gateways
                response_str = llm_inference(system_prompt, message, temperature=temperature, model=effective_model)
                return response_str
                
            except RateLimitError as e:
                wait_time = backoff_factor ** attempt
                print(f"@@@{FLAGS.llm_model}: Rate limit exceeded. Retrying in {wait_time} seconds...")
                time.sleep(wait_time)
            except (APITimeoutError, APIError, APIConnectionError, httpx.TimeoutException, httpx.ReadTimeout, InternalServerError) as e:
                # These exceptions are already handled by the @retry decorator in llm_inference
                # but we can add additional handling here if needed
                raise
            except Exception as e:
                wait_time = backoff_factor ** attempt
                print(f"@@@{FLAGS.llm_model}: An error occurred: {e}. Retrying in {wait_time} seconds...")
                if attempt < retries - 1:
                    time.sleep(wait_time)
                else:
                    raise
        
        # If we reach here, no response after retries
        raise RuntimeError("Failed to get a response after all retries using the configured direct LLM gateway.")
    
    else:
        # Using the original legacy method
        return initiate_chat_with_retry_legacy(
            agent_user,
            agent_coding,
            message=message,
            retries=retries,
            backoff_factor=backoff_factor,
            **kwargs
        )

def call_OpenAI_llm(system_prompt: str, user_prompt: str, temperature: float = None, timeout=300, model: str = None):
    assert FLAGS.LLM_gateaway == 'openai'

    effective_temperature = temperature if temperature is not None else FLAGS.temperature
    effective_model = model if model is not None else FLAGS.llm_model
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY is not set.")

    client = OpenAI(api_key=api_key, timeout=timeout)
    messages = []
    if system_prompt:
        messages.append({"role": "system", "content": system_prompt})
    messages.append({"role": "user", "content": user_prompt})

    output_limit = int(getattr(FLAGS, "max_token", 16384))
    create_kwargs = {
        "model": effective_model,
        "messages": messages,
    }
    if is_o_series_model(effective_model):
        create_kwargs["max_completion_tokens"] = output_limit
        reasoning_effort = os.environ.get(
            "FVRULELEARNER_REASONING_EFFORT", ""
        ).strip().lower()
        if reasoning_effort:
            if reasoning_effort not in {"low", "medium", "high"}:
                raise ValueError(
                    "FVRULELEARNER_REASONING_EFFORT must be empty, "
                    "low, medium, or high for o3-mini"
                )
            create_kwargs["reasoning_effort"] = reasoning_effort
    else:
        create_kwargs["max_tokens"] = min(output_limit, 16384)
        create_kwargs["temperature"] = effective_temperature

    response = client.chat.completions.create(**create_kwargs)
    content = response.choices[0].message.content
    if not content:
        raise RuntimeError(
            "OpenAI returned no visible completion content; increase "
            "FVRULELEARNER_MAX_TOKENS or inspect the response usage."
        )
    return content


def call_Claude_llm(system_prompt: str, user_prompt: str, temperature: float = None, timeout=300, model: str = None):
    assert FLAGS.LLM_gateaway == 'claude'

    effective_temperature = temperature if temperature is not None else FLAGS.temperature
    effective_model = model if model is not None else FLAGS.llm_model
    api_key = os.getenv("ANTHROPIC_API_KEY")
    if not api_key:
        raise RuntimeError("ANTHROPIC_API_KEY is not set.")

    client = anthropic.Anthropic(api_key=api_key, timeout=timeout)
    create_kwargs = {
        "model": effective_model,
        "messages": [{"role": "user", "content": user_prompt}],
        "max_tokens": getattr(FLAGS, "max_token", 4096),
    }
    if system_prompt:
        create_kwargs["system"] = system_prompt
    if not is_o_series_model(effective_model):
        create_kwargs["temperature"] = effective_temperature

    response = client.messages.create(**create_kwargs)
    return "".join(
        block.text for block in response.content if getattr(block, "type", None) == "text"
    )

@retry(
    retry=retry_if_exception_type((
        APITimeoutError,
        APIError,
        APIConnectionError,
        InternalServerError,
        anthropic.APITimeoutError,
        anthropic.APIError,
        anthropic.APIConnectionError,
        anthropic.InternalServerError,
        anthropic.RateLimitError,
        httpx.TimeoutException,
        httpx.ReadTimeout,
    )),
    wait=wait_exponential(multiplier=2, min=3, max=60),
    stop=stop_after_attempt(10),
)
def llm_inference(system_prompt: str, user_prompt: str, temperature: float = None, LLM_gateaway: str = None, model: str = None):
    """Direct LLM inference function for supported prompt-only gateways."""
    if LLM_gateaway is None:
        LLM_gateaway = FLAGS.LLM_gateaway
    
    # Use provided temperature or default from FLAGS
    effective_temperature = temperature if temperature is not None else FLAGS.temperature
    
    # Use provided model or default from FLAGS
    effective_model = model if model is not None else FLAGS.llm_model
    
    # Track inference start time
    inference_start_time = time.time()
    
    # Get tokenizer to count tokens for stats
    tokenizer = get_tokenizer(effective_model)
    total_tokens = count_tokens(tokenizer, system_prompt + user_prompt)

    try:
        if LLM_gateaway == 'openai':
            response = call_OpenAI_llm(system_prompt, user_prompt, effective_temperature, model=effective_model)
        elif LLM_gateaway == 'claude':
            response = call_Claude_llm(system_prompt, user_prompt, effective_temperature, model=effective_model)
        else:
            raise ValueError(f"Invalid model source: {LLM_gateaway}")
            
        # Calculate inference time and log to saver
        inference_time = time.time() - inference_start_time
        saver.save_stats('LLM_runtime', inference_time)
        saver.save_stats('tokens', total_tokens)
        
        return response
        
    except Exception as e:
        # Calculate inference time even for failed calls
        inference_time = time.time() - inference_start_time
        print(f"⚠️ LLM call failed after {inference_time:.2f}s")
        print(f"   Error: {str(e)[:200]}...")
        raise