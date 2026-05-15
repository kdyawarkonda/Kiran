import os
import json
from drug_discovery_agents import AgentManager

def main():
    print("Initializing Multi-Agent Drug Discovery System...")

    # We pass llm=None here to use the fallback simulated tool execution
    # to avoid needing an OpenAI API key for this demonstration.
    # To use a real LLM, instantiate it and pass it to AgentManager(llm=my_llm)
    manager = AgentManager(llm=None)

    # 1. User uploads a protein structure (Galectin-3 variant)
    pdb_path = "drug_discovery_agents/data/dummy_galectin_3.pdb"
    print(f"\n[System] Uploading protein structure: {pdb_path}")

    # 2. AgentManager creates a new agent for this protein
    agent_serial = manager.add_agent(protein_pdb=pdb_path)

    # (Optional) You can add more agents for different variants here:
    # manager.add_agent(protein_pdb="path/to/another_variant.pdb")

    # 3. User provides a list of chemicals in a CSV
    csv_path = "drug_discovery_agents/data/dummy_chemicals.csv"
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
