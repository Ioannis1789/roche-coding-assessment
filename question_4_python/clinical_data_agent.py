"""
==============================================================================
Question 4: GenAI Clinical Data Assistant (LLM & LangChain)
==============================================================================
Description: A Generative AI Assistant that translates natural language
             questions into structured Pandas queries on clinical AE data.
             Uses an LLM to dynamically map user intent to the correct
             dataset variable without hard-coding rules.

Input:       adae.csv (pharmaverseadam::adae exported to CSV)
Output:      Count of unique subjects and list of matching USUBJIDs

Approach:    Prompt -> Parse (LLM) -> Execute (Pandas)
             Supports OpenAI via LangChain, or mock mode for testing.

References:  - LangChain docs: https://python.langchain.com/
             - CDISC ADaM standard for ADAE dataset
==============================================================================
"""

import json
import os
import pandas as pd
from typing import Optional

# --- Schema Definition --------------------------------------------------------
# This dictionary describes the ADAE dataset columns to the LLM so it can
# intelligently map natural language questions to the correct variable.

ADAE_SCHEMA = """
You are an expert clinical trial data analyst. You have access to an Adverse Events (ADAE) dataset
with the following key columns:

| Column    | Description                                         | Example Values                                    |
|-----------|-----------------------------------------------------|---------------------------------------------------|
| USUBJID   | Unique subject identifier                           | "01-701-1015", "01-701-1023"                      |
| AETERM    | Reported term for the adverse event (verbatim)      | "HEADACHE", "DIARRHOEA", "APPLICATION SITE PRURITUS" |
| AEDECOD   | Dictionary-derived term (MedDRA preferred term)     | "Headache", "Diarrhoea", "Application site pruritus" |
| AESOC     | Primary System Organ Class (body system category)   | "NERVOUS SYSTEM DISORDERS", "CARDIAC DISORDERS", "SKIN AND SUBCUTANEOUS TISSUE DISORDERS" |
| AESEV     | Severity/intensity of the adverse event             | "MILD", "MODERATE", "SEVERE"                      |
| AESER     | Serious adverse event flag                          | "Y", "N"                                          |
| AEREL     | Causality (relationship to study drug)              | "RELATED", "NOT RELATED", "POSSIBLY RELATED"      |
| AEOUT     | Outcome of the adverse event                        | "RECOVERED/RESOLVED", "NOT RECOVERED/NOT RESOLVED"|
| AESOC     | System Organ Class                                  | "CARDIAC DISORDERS", "GASTROINTESTINAL DISORDERS"  |
| ACTARM    | Actual treatment arm                                | "Placebo", "Xanomeline High Dose", "Xanomeline Low Dose" |
| TRTEMFL   | Treatment-emergent flag                             | "Y", "N"                                          |
| AESTDTC   | Start date of adverse event                         | "2014-01-03"                                      |
| AEENDTC   | End date of adverse event                           | "2014-02-15"                                      |

IMPORTANT MAPPING RULES:
- If the user asks about "severity" or "intensity" -> use column AESEV
- If the user asks about a specific condition/symptom (e.g., "Headache", "Nausea") -> use column AETERM
- If the user asks about a body system (e.g., "Cardiac", "Skin", "Nervous system") -> use column AESOC
- If the user asks about seriousness -> use column AESER
- If the user asks about causality or relationship to drug -> use column AEREL
- If the user asks about outcome or resolution -> use column AEOUT
- If the user asks about treatment group -> use column ACTARM

The filter_value should match the format used in the dataset. For AESEV, values are uppercase
("MILD", "MODERATE", "SEVERE"). For AETERM, values are uppercase. For AESOC, values are
uppercase. Use case-insensitive partial matching when appropriate.
"""

PARSE_INSTRUCTION = """
Given the user's question below, identify:
1. target_column: The column to filter on
2. filter_value: The value to search for (extracted from the question)

Respond with ONLY a valid JSON object, no markdown, no explanation:
{"target_column": "<column_name>", "filter_value": "<value>"}

User question: {question}
"""


# --- LLM Integration ----------------------------------------------------------

class ClinicalTrialDataAgent:
    """
    An AI-powered agent that translates natural language questions about
    clinical trial adverse events into structured Pandas queries.

    Supports three LLM backends:
    1. OpenAI via LangChain (requires OPENAI_API_KEY)
    2. Anthropic Claude (requires ANTHROPIC_API_KEY)
    3. Mock mode (no API key needed - uses rule-based fallback)
    """

    def __init__(self, data_path: str, llm_provider: str = "auto"):
        """
        Initialize the agent with the ADAE dataset.

        Args:
            data_path: Path to the adae.csv file
            llm_provider: "openai", "anthropic", "mock", or "auto" (tries APIs first)
        """
        # Load the dataset
        self.df = pd.read_csv(data_path)
        print(f"Loaded ADAE dataset: {self.df.shape[0]} rows, {self.df.shape[1]} columns")
        print(f"Unique subjects: {self.df['USUBJID'].nunique()}")

        # Set up LLM provider
        self.llm_provider = self._resolve_provider(llm_provider)
        print(f"LLM Provider: {self.llm_provider}")

        if self.llm_provider == "openai":
            self._init_openai()
        elif self.llm_provider == "anthropic":
            self._init_anthropic()

    def _resolve_provider(self, provider: str) -> str:
        """Auto-detect available LLM provider."""
        if provider != "auto":
            return provider

        if os.getenv("OPENAI_API_KEY"):
            return "openai"
        elif os.getenv("ANTHROPIC_API_KEY"):
            return "anthropic"
        else:
            print("No API keys found. Using mock LLM mode.")
            return "mock"

    def _init_openai(self):
        """Initialize OpenAI via LangChain."""
        try:
            from langchain_openai import ChatOpenAI
            self.llm = ChatOpenAI(model="gpt-4o-mini", temperature=0)
        except ImportError:
            print("langchain_openai not installed. Falling back to mock mode.")
            self.llm_provider = "mock"

    def _init_anthropic(self):
        """Initialize Anthropic Claude."""
        try:
            from langchain_anthropic import ChatAnthropic
            self.llm = ChatAnthropic(model="claude-sonnet-4-20250514", temperature=0)
        except ImportError:
            print("langchain_anthropic not installed. Falling back to mock mode.")
            self.llm_provider = "mock"

    # --- Core Pipeline: Prompt -> Parse -> Execute ----------------------------

    def ask(self, question: str) -> dict:
        """
        Main entry point: takes a natural language question and returns results.

        Args:
            question: Natural language question about the AE dataset

        Returns:
            dict with keys: question, target_column, filter_value,
                            subject_count, subject_ids
        """
        print(f"\n{'='*60}")
        print(f"Question: {question}")
        print(f"{'='*60}")

        # Step 1: Parse - Use LLM to extract structured query
        parsed = self._parse_question(question)
        print(f"Parsed -> column: {parsed['target_column']}, "
              f"value: {parsed['filter_value']}")

        # Step 2: Execute - Apply Pandas filter
        result = self._execute_query(parsed)

        # Step 3: Return results
        print(f"Result -> {result['subject_count']} unique subjects found")
        return result

    def _parse_question(self, question: str) -> dict:
        """
        Use the LLM to parse a natural language question into a structured
        JSON output containing target_column and filter_value.
        """
        if self.llm_provider == "mock":
            return self._mock_parse(question)

        # Build the prompt with schema context and parse instruction
        prompt = ADAE_SCHEMA + "\n\n" + PARSE_INSTRUCTION.format(question=question)

        # Call the LLM
        if self.llm_provider in ("openai", "anthropic"):
            response = self.llm.invoke(prompt)
            response_text = response.content.strip()
        else:
            response_text = ""

        # Parse the JSON response (strip markdown fences if present)
        response_text = response_text.replace("```json", "").replace("```", "").strip()

        try:
            parsed = json.loads(response_text)
            assert "target_column" in parsed and "filter_value" in parsed
            return parsed
        except (json.JSONDecodeError, AssertionError):
            print(f"Warning: Could not parse LLM response: {response_text}")
            print("Falling back to mock parser.")
            return self._mock_parse(question)

    def _mock_parse(self, question: str) -> dict:
        """
        Rule-based fallback parser for when no LLM API is available.
        Demonstrates the expected Prompt -> Parse -> Execute flow.
        """
        q = question.lower()

        # Severity / Intensity keywords
        if any(w in q for w in ["severity", "intense", "intensity", "severe",
                                 "mild", "moderate"]):
            # Extract the severity value
            for val in ["SEVERE", "MODERATE", "MILD"]:
                if val.lower() in q:
                    return {"target_column": "AESEV", "filter_value": val}
            return {"target_column": "AESEV", "filter_value": "SEVERE"}

        # Seriousness keywords
        if any(w in q for w in ["serious", "seriousness", "sar "]):
            if "not serious" in q or "non-serious" in q:
                return {"target_column": "AESER", "filter_value": "N"}
            return {"target_column": "AESER", "filter_value": "Y"}

        # Body system / SOC keywords
        soc_map = {
            "cardiac": "CARDIAC DISORDERS",
            "heart": "CARDIAC DISORDERS",
            "skin": "SKIN AND SUBCUTANEOUS TISSUE DISORDERS",
            "dermat": "SKIN AND SUBCUTANEOUS TISSUE DISORDERS",
            "nervous": "NERVOUS SYSTEM DISORDERS",
            "neuro": "NERVOUS SYSTEM DISORDERS",
            "gastro": "GASTROINTESTINAL DISORDERS",
            "digest": "GASTROINTESTINAL DISORDERS",
            "eye": "EYE DISORDERS",
            "respiratory": "RESPIRATORY, THORACIC AND MEDIASTINAL DISORDERS",
        }
        for keyword, soc_value in soc_map.items():
            if keyword in q:
                return {"target_column": "AESOC", "filter_value": soc_value}

        # Treatment arm keywords
        if any(w in q for w in ["placebo", "treatment", "xanomeline", "high dose",
                                 "low dose"]):
            if "placebo" in q:
                return {"target_column": "ACTARM", "filter_value": "Placebo"}
            elif "high dose" in q:
                return {"target_column": "ACTARM", "filter_value": "Xanomeline High Dose"}
            elif "low dose" in q:
                return {"target_column": "ACTARM", "filter_value": "Xanomeline Low Dose"}

        # Default: treat as a specific AE term search
        # Extract likely AE term by removing question boilerplate words,
        # then use partial matching so "HEADACHE" matches even with extra text.
        term = q
        for remove_word in ["give me", "show me", "find", "list",
                            "the subjects who had", "the subjects with",
                            "which patients experienced", "which patients had",
                            "patients experienced", "patients with",
                            "subjects who had", "subjects with",
                            "who had", "who experienced",
                            "adverse events of", "adverse events",
                            "adverse event of", "adverse event",
                            "all subjects", "subjects", "patients",
                            "of", "ae", "what", "which", "how many",
                            "experienced", "had", "get", "?"]:
            term = term.replace(remove_word, " ")

        # Collapse whitespace and uppercase
        term = " ".join(term.split()).upper()

        if term:
            return {"target_column": "AETERM", "filter_value": term}

        return {"target_column": "AETERM", "filter_value": "HEADACHE"}

    def _execute_query(self, parsed: dict) -> dict:
        """
        Execute the structured query against the ADAE dataframe using Pandas.
        Returns count of unique subjects and their IDs.

        Args:
            parsed: dict with target_column and filter_value from LLM

        Returns:
            dict with question details and results
        """
        col = parsed["target_column"]
        val = parsed["filter_value"]

        # Validate column exists
        if col not in self.df.columns:
            return {
                "target_column": col,
                "filter_value": val,
                "subject_count": 0,
                "subject_ids": [],
                "error": f"Column '{col}' not found in dataset"
            }

        # Apply filter (case-insensitive partial matching for flexibility)
        mask = self.df[col].astype(str).str.upper().str.contains(
            val.upper(), na=False
        )
        filtered = self.df[mask]

        # Get unique subjects
        unique_subjects = filtered["USUBJID"].unique().tolist()

        return {
            "target_column": col,
            "filter_value": val,
            "subject_count": len(unique_subjects),
            "subject_ids": sorted(unique_subjects)
        }


# --- Convenience function for quick queries -----------------------------------

def query_ae_data(data_path: str, question: str,
                  llm_provider: str = "auto") -> dict:
    """
    One-shot function to query the AE dataset with a natural language question.

    Args:
        data_path: Path to adae.csv
        question: Natural language question
        llm_provider: "openai", "anthropic", or "mock"

    Returns:
        Query results dict
    """
    agent = ClinicalTrialDataAgent(data_path, llm_provider)
    return agent.ask(question)