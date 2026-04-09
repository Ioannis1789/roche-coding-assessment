"""
==============================================================================
Question 4: Test Script - GenAI Clinical Data Assistant
==============================================================================
Runs 3 example queries against the ADAE dataset and prints results.
Demonstrates the full Prompt -> Parse -> Execute pipeline.

Usage:
    python test_queries.py

Prerequisites:
    - adae.csv must be in the same directory (or update DATA_PATH below)
    - For LLM mode: set OPENAI_API_KEY or ANTHROPIC_API_KEY env variable
    - For mock mode: no API key needed (default fallback)
==============================================================================
"""

from clinical_data_agent import ClinicalTrialDataAgent

# --- Configuration ------------------------------------------------------------
DATA_PATH = "adae.csv"

# Change to "openai", "anthropic", or "mock" as needed
# "auto" will try API keys first, then fall back to mock
LLM_PROVIDER = "auto"


def print_results(result: dict, question: str):
    """Pretty-print query results."""
    print(f"\n  Question:      {question}")
    print(f"  Target Column: {result['target_column']}")
    print(f"  Filter Value:  {result['filter_value']}")
    print(f"  Subjects Found: {result['subject_count']}")

    if result["subject_count"] > 0:
        # Show first 10 subject IDs to keep output manageable
        ids_display = result["subject_ids"][:10]
        print(f"  Subject IDs (first 10): {ids_display}")
        if result["subject_count"] > 10:
            print(f"  ... and {result['subject_count'] - 10} more")
    else:
        print("  No matching subjects found.")

    print(f"  {'-'*50}")


def main():
    """Run 3 example queries and display results."""
    print("=" * 60)
    print("  GenAI Clinical Data Assistant - Test Script")
    print("=" * 60)

    # Initialize the agent once (reuse for all queries)
    agent = ClinicalTrialDataAgent(DATA_PATH, llm_provider=LLM_PROVIDER)

    # --- Define 3 Example Queries ---------------------------------------------
    queries = [
        # Query 1: Severity-based (maps to AESEV)
        "Give me the subjects who had Adverse events of Moderate severity.",

        # Query 2: Specific condition (maps to AETERM)
        "Which patients experienced Headache?",

        # Query 3: Body system / SOC-based (maps to AESOC)
        "Show me all subjects with cardiac adverse events.",
    ]

    # --- Execute Each Query ---------------------------------------------------
    print("\n" + "=" * 60)
    print("  Running Example Queries")
    print("=" * 60)

    all_results = []
    for i, question in enumerate(queries, 1):
        print(f"\n{'*'*60}")
        print(f"  QUERY {i}")
        print(f"{'*'*60}")

        result = agent.ask(question)
        print_results(result, question)
        all_results.append(result)

    # --- Summary --------------------------------------------------------------
    print("\n" + "=" * 60)
    print("  SUMMARY")
    print("=" * 60)
    for i, (q, r) in enumerate(zip(queries, all_results), 1):
        print(f"  Q{i}: {q[:50]}...")
        print(f"      -> {r['target_column']}={r['filter_value']} "
              f"-> {r['subject_count']} subjects")
    print("=" * 60)
    print("  Test script completed successfully!")


if __name__ == "__main__":
    main()