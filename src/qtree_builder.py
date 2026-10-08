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
"""
Q-Tree Builder for Self-Learning SVA Generation

This module implements a Question Tree (Q-Tree) approach for analyzing differences
between generated and reference assertions, and generating rules to improve them.
"""

from enum import Enum
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Set, Tuple
import json
import os
import re
import time
import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
from utils_agent import initiate_chat_with_retry
from config import FLAGS
from operator_selector import OPERATOR_CATEGORIES, rank_operator_categories


class QuestionLevel(Enum):
    """Levels in the Q-Tree hierarchy"""
    BACKGROUND = "background"
    EXPLORATORY = "exploratory"  # Level 1: High-level analysis questions
    SPECIFIC_ANALYSIS = "specific_analysis"  # Level 2: Specific difference analysis
    RULE_GENERATION = "rule_generation"  # Level 3: Generate actual rules/suggestions


@dataclass
class QuestionNode:
    """Node in the Q-Tree structure"""
    id: str
    question: str
    level: QuestionLevel
    parent_id: Optional[str] = None
    children: List[str] = field(default_factory=list)
    answer: Optional[str] = None
    rules_generated: List[str] = field(default_factory=list)
    metrics: Dict[str, Any] = field(default_factory=dict)


class QTreeBuilder:
    """Builds Q-Tree for assertion analysis and rule generation"""
    
    def __init__(self, agents: Dict[str, Any], config_flags=None):
        self.agents = agents
        # Support for different agents per level - default to using the same Reflection agent for all levels
        # self.level_agents = {
        #     QuestionLevel.EXPLORATORY: agents.get("Reflection_o1", agents.get("Reflection")),
        #     QuestionLevel.SPECIFIC_ANALYSIS: agents.get("Reflection_gpt4o", agents.get("Reflection")),
        #     QuestionLevel.RULE_GENERATION: agents.get("Reflection_gpt4o", agents.get("Reflection"))
        # }
        self.nodes: Dict[str, QuestionNode] = {}
        self.tree_results = []
        self.config_flags = config_flags if config_flags is not None else FLAGS
        self.max_questions_per_level = getattr(
            self.config_flags, "question_tree_width", 3
        )
        self.operator_selection_method = getattr(
            self.config_flags, "operator_selection_method", "shuffle"
        )
        self.oracle = getattr(self.config_flags, "oracle", True)
        if self.operator_selection_method not in {"shuffle", "jev"}:
            raise ValueError("operator_selection_method must be 'shuffle' or 'jev'")
        if type(self.oracle) is not bool:
            raise TypeError("oracle must be a bool")
        if (
            type(self.max_questions_per_level) is not int
            or not 1 <= self.max_questions_per_level <= len(OPERATOR_CATEGORIES)
        ):
            raise ValueError("question_tree_width must be an integer from 1 to 5")
        self._last_operator_selection = None
        self._last_diversity_metrics = None
        self._row_data = None  # Store row data for later access
        self.qa_time = 0.0
        
    def build_qtree_for_assertion_pair(self, 
                                     generated_assertion: str, 
                                     reference_assertion: str,
                                     row: Any,
                                     metrics: Dict[str, Any]) -> List[QuestionNode]:
        """
        Build a Q-Tree to analyze differences between generated and reference assertions
        
        Tree Structure:
        Root: Background Knowledge (context about the problem)
        Level 1: Exploratory questions about major differences
        Level 2: Specific analysis questions for each difference
        Level 3: Rule generation based on the analysis
        """
        tree_nodes = []
        node_counter = 0
        
        # Store row data for later use
        self._row_data = row
        # print(f"row: {row}")
        # breakpoint()
        
        print(f"\n=== BUILDING Q-TREE FOR ASSERTION ANALYSIS ===")
        
        # Root: Background Knowledge
        background_knowledge = self._get_background_knowledge(row, generated_assertion, reference_assertion)
        
        # Level 1: Generate exploratory questions
        exploratory_questions = self._generate_exploratory_questions(
            generated_assertion, reference_assertion, metrics, row
        )
        exploratory_nodes = []
        
        for question in exploratory_questions:
            node = QuestionNode(
                id=f"explore_{node_counter}",
                question=question,
                level=QuestionLevel.EXPLORATORY,
                parent_id=None,
                metrics=metrics
            )
            exploratory_nodes.append(node)
            tree_nodes.append(node)
            self.nodes[node.id] = node
            node_counter += 1
            
            # Get answer for exploratory question
            node.answer = self._answer_exploratory_question(
                question, generated_assertion, reference_assertion, row
            )
            
        # Level 2: Generate specific analysis questions
        specific_nodes = []
        for parent_node in exploratory_nodes:
            specific_questions = self._generate_specific_analysis_questions(
                parent_node, generated_assertion, reference_assertion
            )
            
            for question in specific_questions:
                specific_node = QuestionNode(
                    id=f"specific_{node_counter}",
                    question=question,
                    level=QuestionLevel.SPECIFIC_ANALYSIS,
                    parent_id=parent_node.id,
                    metrics=metrics
                )
                parent_node.children.append(specific_node.id)
                specific_nodes.append(specific_node)
                tree_nodes.append(specific_node)
                self.nodes[specific_node.id] = specific_node
                node_counter += 1
                
                # Get answer for specific question
                specific_node.answer = self._answer_specific_question(
                    question, parent_node.answer, generated_assertion, reference_assertion
                )
                print(f"    Level 2 → {question[:100]}...")
                
        # Level 3: Generate rules based on analysis
        for parent_node in specific_nodes:
            rules = self._generate_rules_from_analysis(
                parent_node, generated_assertion, reference_assertion
            )
            
            rule_node = QuestionNode(
                id=f"rule_{node_counter}",
                question=f"Generate rules to fix: {parent_node.question}...",
                level=QuestionLevel.RULE_GENERATION,
                parent_id=parent_node.id,
                rules_generated=rules,
                metrics=metrics
            )
            parent_node.children.append(rule_node.id)
            tree_nodes.append(rule_node)
            self.nodes[rule_node.id] = rule_node
            node_counter += 1
            
            print(f"      Level 3 → Generated {len(rules)} rule")
            
        print(f"\nGenerated {len(tree_nodes)} nodes in Q-Tree")
        return tree_nodes
    
    def _get_background_knowledge(self, row, generated, reference):
        """Get background knowledge about the assertion problem"""
        return f"""
        Task: Generate SVA assertions for the following:
        Natural Language: {row.prompt}
        Testbench: {row.testbench}
        Generated Assertion: {generated}
        Reference Assertion: {reference}
        
        Key SVA Grammar Elements:
        1. Clock and Reset Control
           - @(posedge clk) - Assertions are sampled at positive clock edge
           - disable iff (tb_reset) - Disables assertion checking during reset

        2. Logical Operators
           - && (AND), || (OR), ! (NOT) for boolean logic
           - | - Reduction OR (e.g., |tb_req checks if any bit is 1)
           - & - Bitwise AND for masking operations

        3. Comparison Operators
           - === - Case equality (4-state comparison, includes X and Z)
           - !== - Case inequality
           - ==, != - Logical equality/inequality
           - <, >, <=, >= - Relational operators

        4. Temporal Operators
           - |-> - Overlapping implication (if antecedent then consequent in same cycle)
           - |=> - Non-overlapping implication (would be antecedent then consequent in next cycle)
           - ##[n:m] - Cycle delay range (n to m cycles)
           - ##[0:$] - Eventually (from now to infinity)
           - strong() - Strong sequence (must complete)

        5. Special SVA Functions
           - $onehot() - Checks if exactly one bit is high
           - $onehot0() - Checks if zero or one bit is high
        """
    
    
    def _select_operator_categories(self, gen_assertion, ref_assertion, row):
        """Choose analysis categories for the current assertion."""
        started = time.time()
        scores = {}

        if self.operator_selection_method == "shuffle":
            import random

            categories = list(OPERATOR_CATEGORIES)
            random.shuffle(categories)
            selected = categories[:self.max_questions_per_level]
        else:
            selected, scores = rank_operator_categories(
                requirement=row.prompt,
                generated_sva=gen_assertion,
                reference_sva=ref_assertion if self.oracle else "",
                top_k=self.max_questions_per_level,
                oracle=self.oracle,
            )

        self._last_operator_selection = {
            "method": self.operator_selection_method,
            "oracle": self.oracle,
            "reference_used": self.operator_selection_method == "jev" and self.oracle,
            "selected_categories": selected,
            "scores": scores,
            "selection_seconds": time.time() - started,
            "generated_sva": gen_assertion,
        }
        print(f"Operator selection method: {self.operator_selection_method}")
        print(f"Jev reference access: {self._last_operator_selection['reference_used']}")
        print(f"Selected categories: {selected}")
        if scores:
            print(f"Jev scores: {scores}")
        return selected

    def _generate_exploratory_questions(self, gen_assertion: str, ref_assertion: str, 
                                      metrics: Dict[str, Any], row: Any) -> List[str]:
        """Generate exploratory questions based on assertion differences"""
        selected_keywords = self._select_operator_categories(
            gen_assertion, ref_assertion, row
        )

        # Build prompt for LLM to generate questions
        full_background = self._get_background_knowledge(row, gen_assertion, ref_assertion)
        
        # Create keyword guidance for multiple aspects
        keyword_list = ", ".join(selected_keywords)
        
        prompt = f"""
---
** Background Knowledge: $#${full_background}$#$
---
** Analysis Focus: $#$Cover DIFFERENT aspects: {keyword_list}$#$
---
Context: You have been provided with:
* Generated assertion that may have errors
* Reference assertion that is correct
* Analysis keywords: {keyword_list}

Your Goal:
- Generate EXACTLY {self.max_questions_per_level} exploratory questions about assertion differences
- Each question MUST focus on a DIFFERENT aspect from: {keyword_list}
- Question 1: Focus on {selected_keywords[0] if len(selected_keywords) > 0 else 'operators'}
- Question 2: Focus on {selected_keywords[1] if len(selected_keywords) > 1 else 'timing'}
- Question 3: Focus on {selected_keywords[2] if len(selected_keywords) > 2 else 'structure'}
- Ensure questions explore DISTINCT dimensions of the problem

Guidelines:
- Questions should focus on operator-level differences
- Analyze specific operators used in each assertion
- Consider operator placement, precedence, and correctness
- Each question should identify specific operators that need attention
- IMPORTANT: Each question MUST focus on its assigned keyword aspect to ensure diversity

Keyword Guidance (match question number to keyword):
- logical_operators: Focus on &&, ||, !, and their usage in conditions
- temporal_operators: Analyze |-> vs |=>, ##[n:m], and timing constructs
- comparison_operators: Examine === vs ==, !== vs !=, and relational operators
- implication_operators: Distinguish between overlapping (|->) and non-overlapping (|=>) implications
- bitwise_operators: Consider &, |, ~, and reduction operators in signal operations

Constraints:
- Generate exactly {self.max_questions_per_level} questions
- Each question must end with "?"
- Questions should be concise (one sentence each)
- Each question must address a DIFFERENT keyword aspect (no overlap!)
- Avoid generating similar questions - maximize diversity across the {self.max_questions_per_level} aspects

OUTPUT FORMAT:
Provide questions as a numbered list:
1. [First question]
2. [Second question]
3. [Third question]
---
Generated Assertion: {gen_assertion}
Reference Assertion: {ref_assertion}
"""
        
        # Get questions from LLM - use o1 model for exploratory questions
        response = initiate_chat_with_retry(
            self.agents["user"],
            self.agents["Reflection"],
            message=prompt,
            model=FLAGS.llm_model
        )
        
        # Parse LLM response to extract questions
        questions = []
        lines = response.strip().split('\n')
        
        for line in lines:
            line = line.strip()
            # Skip empty lines and lines that look like headers
            if line and not line.endswith(':') and len(line) > 10:
                # Remove leading numbers, bullets, etc.
                cleaned = re.sub(r'^[\d\.\-\*\s]+', '', line).strip()
                if cleaned and '?' in cleaned:
                    questions.append(cleaned)
        
        # If LLM didn't generate enough questions, add fallback questions
        if len(questions) < 2:
            fallback_keyword = (
                selected_keywords[0] if selected_keywords else "operators"
            )
            fallback_questions = [
                f"Considering {fallback_keyword}, which specific operators are different between the generated and reference assertions?",
                f"Considering {fallback_keyword}, are the operators used correctly for the intended behavior?",
                f"Considering {fallback_keyword}, what operator changes would fix the assertion?"
            ]
            
            for fallback in fallback_questions:
                if len(questions) < self.max_questions_per_level:
                    questions.append(fallback)
        
        final_questions = questions[:self.max_questions_per_level]
        
        # Calculate semantic diversity of generated questions
        diversity_metrics = self.calculate_semantic_diversity(final_questions)
        
        # Log diversity information
        # if hasattr(FLAGS, 'verbose') and FLAGS.verbose:
            # print(f"\n  Semantic Diversity Analysis:")
            # print(f"    - Overall Diversity Score: {diversity_metrics.get('overall_diversity_score', 0):.3f}")
            # print(f"    - Semantic Diversity: {diversity_metrics.get('semantic_diversity_score', 0):.3f}")
            # print(f"    - Interpretation: {diversity_metrics.get('interpretation', 'N/A')}")
            # print(f"    - Vocabulary Richness: {diversity_metrics.get('vocabulary_richness', 0):.3f}")
            
            # Show similarity distribution
            # sim_dist = diversity_metrics.get('similarity_distribution', {})
            # if sim_dist:
            #     print(f"    - Similarity Distribution:")
            #     print(f"        Very Different: {sim_dist.get('very_different', 0)}")
            #     print(f"        Different: {sim_dist.get('different', 0)}")
            #     print(f"        Moderate: {sim_dist.get('moderate', 0)}")
            #     print(f"        Similar: {sim_dist.get('similar', 0)}")
            #     print(f"        Very Similar: {sim_dist.get('very_similar', 0)}")
        
        # Store diversity metrics for later use
        self._last_diversity_metrics = diversity_metrics
        
        return final_questions
    
    def _answer_exploratory_question(self, question, generated, reference, row):
        """Get answer for an exploratory question using the reflection agent"""
        # Extract keyword from question if present
        keyword_focus = ""
        if "Considering" in question:
            keyword_part = question.split(",")[0]
            keyword_focus = f"\nAnalysis Focus: {keyword_part}"
        
        # Get full background knowledge including SVA grammar
        background = self._get_background_knowledge(row, generated, reference)
        
        prompt = f"""
---
** Background Knowledge: $#${background}$#$
---
** Problem: $#${question}$#${keyword_focus}
---
Context: You have been provided with:
* Natural language description of the intended behavior
* Generated assertion that may contain errors
* Reference assertion that is correct

Your Goal:
- Identify which aspects of the assertions are relevant to this question
- Analyze the specific differences that relate to the question
- Provide concrete insights about what needs to be fixed

Guidelines:
- Focus on elements that directly address the exploratory question
- Consider signal usage, timing relationships, operators, and logical structure
- Think about what makes the reference assertion correct and the generated one incorrect
- Be specific about which parts of the assertions need attention

Constraints:
- Provide a focused analysis (2-3 paragraphs)
- Reference specific signals, operators, or constructs when applicable
- Explain the impact of the identified differences

OUTPUT FORMAT:
Provide your analysis in clear paragraphs addressing:
1. What specific differences relate to the question
2. Why these differences matter for correctness
3. Key insights for fixing the issue
---
Generated Assertion: {generated}
Reference Assertion: {reference}
"""
        
        start_time = time.time()
        response = initiate_chat_with_retry(
            self.agents["user"], 
            self.agents["Reflection"], 
            message=prompt
        )
        self.qa_time += time.time() - start_time
        return response
    
    def _generate_specific_analysis_questions(self, parent_node, generated, reference):
        """Generate specific analysis questions based on exploratory answer content"""
        # Analyze the parent answer to generate relevant follow-up questions
        answer_text = parent_node.answer.lower() if parent_node.answer else ""
        questions = []
        
        # Generate questions based on content patterns in the answer
        if "signal" in answer_text and ("missing" in answer_text or "extra" in answer_text):
            questions.append("What specific signals need to be added or removed?")
            questions.append("How should these signals be integrated into the assertion?")
        
        elif "timing" in answer_text or "delay" in answer_text or "cycle" in answer_text:
            questions.append("What is the correct timing relationship or delay?")
            # questions.append("Should the implication be overlapping (|->) or non-overlapping (|=>)?")
            questions.append("How should the temporal sequence be structured in the assertion?")
        
        elif "operator" in answer_text or "comparison" in answer_text:
            questions.append("Which operators need to be changed and how?")
            questions.append("What is the correct logical structure for this assertion?")
        
        elif "condition" in answer_text or "antecedent" in answer_text or "consequent" in answer_text:
            questions.append("What belongs in the condition vs. the result part?")
            questions.append("How should the implication be structured?")
        
        # Generic follow-ups if no specific pattern matched
        if not questions:
            questions.extend([
                "What specific changes are needed to fix this issue?",
                "How can this be implemented correctly?"
            ])
        
        # Add implementation question if answer suggests a fix
        if "should be" in answer_text or "needs to" in answer_text:
            questions.append("What is the exact implementation for this correction?")
        
        return questions[:2]  # Limit to 2 specific questions per exploratory question
    
    def _answer_specific_question(self, question, parent_answer, generated, reference):
        """Get answer for a specific analysis question"""
        prompt = f"""
---
** Background Analysis: $#${parent_answer}$#$
---
** Specific Question: $#${question}$#$
---
Context: You have been provided with:
* Previous analysis of the assertion differences
* A specific follow-up question requiring detailed answer
* Both generated and reference assertions

Your Goal:
- Answer the specific question based on the previous analysis
- Provide concrete, actionable details
- Focus on implementation-level specifics

Guidelines:
- Build upon the insights from the background analysis
- Be precise about signals, operators, timing, or structure changes needed
- Provide exact syntax or patterns when applicable
- Consider edge cases or special conditions

Constraints:
- Keep answer focused and concise (1-2 paragraphs)
- Include specific examples from the assertions
- Make suggestions directly implementable

OUTPUT FORMAT:
Provide a direct answer that includes:
1. Specific answer to the question
2. Concrete examples or syntax when applicable
3. Any important considerations or caveats
---
Generated Assertion: {generated}
Reference Assertion: {reference}
"""
        
        start_time = time.time()
        response = initiate_chat_with_retry(
            self.agents["user"], 
            self.agents["Reflection"], 
            message=prompt
        )
        self.qa_time += time.time() - start_time
        return response
    
    def _generate_rules_from_analysis(self, analysis_node, generated, reference):
        """Generate concrete rules based on the analysis"""
        prompt = f"""
---
** Detailed Analysis: $#${analysis_node.answer}$#$
---
** Task: $#$Generate actionable rules for fixing assertion errors$#$
---
Context: You have been provided with:
* Detailed analysis of a specific assertion issue
* Generated assertion with errors
* Reference assertion showing correct implementation

Your Goal:
- Extract ONE concrete, implementable rule from the analysis
- This single rule should address the most critical fix needed
- The rule should be general enough to apply to similar cases

Guidelines:
- Focus on the most important pattern that can be reused
- Reference specific constructs (signals, operators, timing)
- Make the rule precise and unambiguous
- Prioritize the fix that would have the biggest impact

Rule Format Requirements:
- The rule must be one sentence
- Start the rule with "- "
- Be specific about the action needed
- Include a concrete example when helpful

OUTPUT FORMAT:
Generate exactly 1 rule.

Examples of good rules:
- Replace non-overlapping implication (|=>) with overlapping (|->) when checking immediate response
- Add missing enable signal to antecedent when the specification mentions conditional behavior
- Use && operator instead of || when multiple conditions must be satisfied simultaneously
---
Generated Assertion: {generated}
Reference Assertion: {reference}
"""
        
        response = initiate_chat_with_retry(
            self.agents["user"], 
            self.agents["Reflection"], 
            message=prompt
        )
        
        # Extract rules from response - only take the first rule
        rules = []
        for line in response.split('\n'):
            if line.strip().startswith('- '):
                rules.append(line.strip())
                break  # Only take the first rule since we want one rule per branch
                
        return rules
    
    def get_aggregated_rules(self) -> List[str]:
        """Aggregate all rules from the Q-Tree"""
        all_rules = []
        for node_id, node in self.nodes.items():
            if node.level == QuestionLevel.RULE_GENERATION:
                all_rules.extend(node.rules_generated)
        
        # Remove duplicates while preserving order
        seen = set()
        unique_rules = []
        for rule in all_rules:
            if rule not in seen:
                seen.add(rule)
                unique_rules.append(rule)
                
        return unique_rules
    
    
    def get_qtree_data(self, task_id: str = None):
        """Get Q-Tree data structure (without saving to disk)"""
        tree_data = {
            # "task_id": task_id,
            # "design_name": self._row_data.design_name if self._row_data else None,  # Using task_id as design_id since there's no separate design_id field
            "signal_based": True,
            "operator_selection": self._last_operator_selection,
            "nodes": [],
            "question_analysis": self._get_question_coverage(),
            "semantic_diversity_metrics": self._last_diversity_metrics if self._last_diversity_metrics else {},
            # "prompt": self._row_data.prompt if self._row_data else None  # Include the original prompt
            # testbench is now stored at top level in saver.py, not inside qtree_data
        }
        
        for node_id, node in self.nodes.items():
            node_data = {
                "id": node.id,
                "question": node.question,
                "level": node.level.value,
                "parent_id": node.parent_id,
                "children": node.children,
                "answer": node.answer,
                "rules_generated": node.rules_generated
            }
            tree_data["nodes"].append(node_data)
        
        return tree_data
    
    def calculate_semantic_diversity(self, questions: List[str]) -> Dict[str, Any]:
        """
        Calculate semantic diversity of questions using TF-IDF and cosine similarity.
        This provides a more sophisticated measure than simple word overlap.
        
        Args:
            questions: List of questions to analyze
            
        Returns:
            Dictionary containing semantic diversity metrics
        """
        if not questions or len(questions) < 2:
            return {
                "error": "Need at least 2 questions for diversity analysis",
                "semantic_diversity_score": 0,
                "interpretation": "Insufficient questions"
            }
        
        try:
            # Create TF-IDF vectors for the questions
            vectorizer = TfidfVectorizer(
                lowercase=True,
                stop_words='english',
                ngram_range=(1, 3),  # Use unigrams, bigrams, and trigrams
                max_features=100
            )
            
            # Transform questions to TF-IDF vectors
            tfidf_matrix = vectorizer.fit_transform(questions)
            
            # Calculate pairwise cosine similarity
            similarity_matrix = cosine_similarity(tfidf_matrix)
            
            # Extract upper triangle (excluding diagonal) for pairwise similarities
            n = len(questions)
            pairwise_similarities = []
            for i in range(n):
                for j in range(i + 1, n):
                    pairwise_similarities.append(similarity_matrix[i, j])
            
            # Calculate diversity metrics
            avg_similarity = np.mean(pairwise_similarities)
            min_similarity = np.min(pairwise_similarities)
            max_similarity = np.max(pairwise_similarities)
            std_similarity = np.std(pairwise_similarities)
            
            # Semantic diversity score (1 - average similarity)
            semantic_diversity = 1 - avg_similarity
            
            # Additional metrics
            # Entropy-based diversity (higher entropy = more diverse)
            if len(pairwise_similarities) > 0:
                # Normalize similarities to probabilities
                sim_probs = np.array(pairwise_similarities) / np.sum(pairwise_similarities)
                # Calculate entropy
                entropy = -np.sum(sim_probs * np.log(sim_probs + 1e-10))
                max_entropy = np.log(len(pairwise_similarities))
                normalized_entropy = entropy / max_entropy if max_entropy > 0 else 0
            else:
                normalized_entropy = 0
            
            # Vocabulary richness
            all_features = set()
            for q in questions:
                tokens = vectorizer.build_analyzer()(q)
                all_features.update(tokens)
            
            vocab_richness = len(all_features) / (len(questions) * 10)  # Normalized by expected tokens
            
            # Overall semantic diversity score (weighted combination)
            overall_score = (
                semantic_diversity * 0.5 +
                normalized_entropy * 0.3 +
                min(vocab_richness, 1.0) * 0.2
            )
            
            # Create detailed results
            results = {
                "semantic_diversity_score": semantic_diversity,
                "overall_diversity_score": overall_score,
                "avg_similarity": avg_similarity,
                "min_similarity": min_similarity,
                "max_similarity": max_similarity,
                "similarity_std": std_similarity,
                "normalized_entropy": normalized_entropy,
                "vocabulary_richness": vocab_richness,
                "unique_features": len(all_features),
                "num_questions": len(questions),
                "pairwise_comparisons": len(pairwise_similarities),
                "interpretation": self._interpret_semantic_diversity(overall_score),
                "similarity_distribution": {
                    "very_similar": sum(1 for s in pairwise_similarities if s > 0.8),
                    "similar": sum(1 for s in pairwise_similarities if 0.6 < s <= 0.8),
                    "moderate": sum(1 for s in pairwise_similarities if 0.4 < s <= 0.6),
                    "different": sum(1 for s in pairwise_similarities if 0.2 < s <= 0.4),
                    "very_different": sum(1 for s in pairwise_similarities if s <= 0.2)
                }
            }
            
            # Add individual question analysis
            question_uniqueness = []
            for i, q in enumerate(questions):
                # Average similarity of this question to all others
                other_sims = [similarity_matrix[i, j] for j in range(n) if i != j]
                avg_sim_to_others = np.mean(other_sims) if other_sims else 0
                uniqueness = 1 - avg_sim_to_others
                question_uniqueness.append({
                    "question": q[:100] + "..." if len(q) > 100 else q,
                    "uniqueness_score": uniqueness,
                    "avg_similarity_to_others": avg_sim_to_others
                })
            
            results["question_uniqueness"] = sorted(
                question_uniqueness, 
                key=lambda x: x["uniqueness_score"], 
                reverse=True
            )
            
            return results
            
        except Exception as e:
            return {
                "error": f"Failed to calculate semantic diversity: {str(e)}",
                "semantic_diversity_score": 0,
                "interpretation": "Error in calculation"
            }
    
    def _interpret_semantic_diversity(self, score: float) -> str:
        """Provide interpretation of semantic diversity score"""
        if score >= 0.8:
            return "Excellent semantic diversity - questions explore very different aspects"
        elif score >= 0.65:
            return "Good semantic diversity - questions cover varied perspectives"
        elif score >= 0.5:
            return "Moderate semantic diversity - reasonable variety with some overlap"
        elif score >= 0.35:
            return "Low semantic diversity - questions have significant overlap"
        else:
            return "Poor semantic diversity - questions are semantically very similar"
    
    def _get_question_coverage(self) -> Dict[str, Any]:
        """Analyze question coverage and patterns"""
        exploratory_nodes = [n for n in self.nodes.values() if n.level == QuestionLevel.EXPLORATORY]
        specific_nodes = [n for n in self.nodes.values() if n.level == QuestionLevel.SPECIFIC_ANALYSIS]
        
        # Analyze question topics based on keywords
        topics = {"signals": 0, "timing": 0, "operators": 0, "structure": 0, "other": 0}
        
        for node in exploratory_nodes + specific_nodes:
            question_lower = node.question.lower()
            if "signal" in question_lower:
                topics["signals"] += 1
            elif any(word in question_lower for word in ["timing", "delay", "cycle", "clock"]):
                topics["timing"] += 1
            elif any(word in question_lower for word in ["operator", "comparison", "&&", "||"]):
                topics["operators"] += 1
            elif any(word in question_lower for word in ["structure", "antecedent", "consequent", "implication"]):
                topics["structure"] += 1
            else:
                topics["other"] += 1
        
        return {
            "exploratory_questions": len(exploratory_nodes),
            "specific_questions": len(specific_nodes),
            "total_questions": len(exploratory_nodes) + len(specific_nodes),
            "question_topics": topics
        }