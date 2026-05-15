import os
import argparse
import pandas as pd
from drug_discovery_agents import AgentManager

def main():
    parser = argparse.ArgumentParser(description="Run Multi-Agent Drug Discovery System")
    parser.add_argument("--pdb", type=str, default="drug_discovery_agents/data/dummy_galectin_3.pdb",
                        help="Path to the protein PDB file")
    parser.add_argument("--csv", type=str, default="drug_discovery_agents/data/dummy_chemicals.csv",
                        help="Path to the chemical dataset CSV file")
    args = parser.parse_args()

    print("==================================================")
    print("  MULTI-AGENT DRUG DISCOVERY SYSTEM INITIALIZED   ")
    print("==================================================\n")

    manager = AgentManager(llm=None)

    pdb_path = args.pdb
    if not os.path.exists(pdb_path):
        print(f"Error: PDB file not found at {pdb_path}")
        return
    print(f"[System] Target Protein Structure: {pdb_path}")

    # In a real scenario, you could loop through multiple PDB files and add multiple agents here.
    # For now, we add one agent for the provided PDB file.
    manager.add_agent(protein_pdb=pdb_path)

    csv_path = args.csv
    if not os.path.exists(csv_path):
        print(f"Error: CSV file not found at {csv_path}")
        return
    print(f"[System] Chemical Dataset: {csv_path}")

    results = manager.run_chemical_screening(csv_path=csv_path, max_workers=4)

    if not results:
        print("No results generated.")
        return

    # Convert results to a pandas DataFrame for tabular formatting
    df = pd.DataFrame(results)

    # Sort the dataframe by 'Drug Score' (lowest score is best)
    df_sorted = df.sort_values(by="Drug Score", ascending=True).reset_index(drop=True)

    # Print the tabular results
    print("\n\n==================================================")
    print("             FINAL SCREENING RESULTS              ")
    print("          (Sorted from Best to Worst)             ")
    print("==================================================\n")

    # Configure pandas to show all columns and wide rows
    pd.set_option('display.max_columns', None)
    pd.set_option('display.width', 1000)
    pd.set_option('display.max_colwidth', 80)

    print(df_sorted.to_string(index=True))

    print("\n\nNote: 'Drug Score' is calculated as: Affinity + (Toxicity * 10) - (Stability * 10). Lower is better.")
    print("Results saved to output_results.csv")

    # Save to CSV for the user
    df_sorted.to_csv("output_results.csv", index=False)

if __name__ == "__main__":
    main()
