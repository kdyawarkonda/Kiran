import os
import argparse
from drug_discovery_agents import AgentManager

def main():
    parser = argparse.ArgumentParser(description="Run Multi-Agent Drug Discovery System")
    parser.add_argument("--pdb", type=str, default="drug_discovery_agents/data/dummy_galectin_3.pdb",
                        help="Path to the protein PDB file")
    parser.add_argument("--csv", type=str, default="drug_discovery_agents/data/dummy_chemicals.csv",
                        help="Path to the chemical dataset CSV file")
    args = parser.parse_args()

    print("Initializing Multi-Agent Drug Discovery System...")

    # We pass llm=None here to use the fallback simulated tool execution
    # to avoid needing an OpenAI API key for this demonstration.
    # To use a real LLM, instantiate it and pass it to AgentManager(llm=my_llm)
    manager = AgentManager(llm=None)

    # 1. User uploads a protein structure (Galectin-3 variant)
    pdb_path = args.pdb
    if not os.path.exists(pdb_path):
        print(f"Error: PDB file not found at {pdb_path}")
        return

    print(f"\n[System] Uploading protein structure: {pdb_path}")

    # 2. AgentManager creates a new agent for this protein
    agent_serial = manager.add_agent(protein_pdb=pdb_path)

    # 3. User provides a list of chemicals in a CSV
    csv_path = args.csv
    if not os.path.exists(csv_path):
        print(f"Error: CSV file not found at {csv_path}")
        return

    print(f"\n[System] Loading chemical dataset: {csv_path}")

    # 4. Run the screening process in parallel
    print(f"\n[System] Starting analysis...")
    results = manager.run_chemical_screening(csv_path=csv_path, max_workers=2)

    # 5. Output the results
    print("\n--- Final Analysis Results ---")
    for res in results:
        print(f"\nAgent: {res['agent_serial']} | Chemical: {res['chemical_name']} ({res['smiles']})")
        print(f"Result:\n{res['analysis_result']}")
        print("-" * 40)

if __name__ == "__main__":
    main()
