import concurrent.futures
import pandas as pd
import json
import re
from typing import List, Dict, Any
from langchain.agents import initialize_agent, AgentType
from langchain_community.chat_models import ChatOpenAI

from .tools import analyze_stability, analyze_efficacy, analyze_side_effects, find_biological_pathways, analyze_docking_and_inhibition

class ProteinAgent:
    def __init__(self, serial_number: str, protein_pdb: str, llm=None):
        self.serial_number = serial_number
        self.protein_pdb = protein_pdb

        if llm is None:
            self.llm = None
        else:
            self.llm = llm

        self.tools = [
            analyze_stability,
            analyze_efficacy,
            analyze_side_effects,
            find_biological_pathways,
            analyze_docking_and_inhibition
        ]

        if self.llm:
            self.agent = initialize_agent(
                tools=self.tools,
                llm=self.llm,
                agent=AgentType.ZERO_SHOT_REACT_DESCRIPTION,
                verbose=False,
                handle_parsing_errors=True
            )
        else:
            self.agent = None

    def _extract_metric(self, text: str, pattern: str) -> float:
        match = re.search(pattern, text)
        if match:
            return float(match.group(1))
        return 0.0

    def analyze_chemical(self, smiles: str, name: str) -> Dict[str, Any]:
        """
        Runs the agent on a single chemical.
        Returns a dictionary containing structured metrics for tabular display.
        """
        # When bypassing LLM for simulated execution:
        if not self.agent:
            efficacy_raw = analyze_efficacy.invoke(f"{smiles},{self.protein_pdb}")
            pathway_raw = find_biological_pathways.invoke(smiles)
            side_effect_raw = analyze_side_effects.invoke(smiles)
            stability_raw = analyze_stability.invoke(smiles)
            docking_raw = analyze_docking_and_inhibition.invoke(f"{smiles},{self.protein_pdb}")
        else:
            # If an LLM is used, we prompt it to use tools and we will still manually invoke the tools
            # to guarantee structured JSON output for the table, OR we can parse the LLM output.
            # For robustness in tabular rendering, forced tool invocation is more reliable.
            efficacy_raw = analyze_efficacy.invoke(f"{smiles},{self.protein_pdb}")
            pathway_raw = find_biological_pathways.invoke(smiles)
            side_effect_raw = analyze_side_effects.invoke(smiles)
            stability_raw = analyze_stability.invoke(smiles)
            docking_raw = analyze_docking_and_inhibition.invoke(f"{smiles},{self.protein_pdb}")

            # The LLM can still generate a summary
            prompt = f"""You are Agent {self.serial_number}. Analyze '{name}' (SMILES: {smiles}) for protein {self.protein_pdb}. Keep summary to 2 sentences."""
            try:
                summary = self.agent.run(prompt)
            except:
                summary = "Analysis complete."

        # Extract numerical values for sorting and scoring
        affinity = self._extract_metric(efficacy_raw, r"Affinity: (-?\d+\.\d+)")
        toxicity = self._extract_metric(side_effect_raw, r"Risk: (\d+\.\d+)")
        stability = self._extract_metric(stability_raw, r"Score: (\d+\.\d+)")

        # Calculate a simple "Drug Score" (lower affinity is better, lower toxicity is better, higher stability is better)
        # Score = Affinity (more negative is better) + (Toxicity * 10) - (Stability * 10)
        # Therefore, a LOWER score is a BETTER drug.
        drug_score = affinity + (toxicity * 10) - (stability * 10)

        return {
            "Agent": self.serial_number,
            "Protein": self.protein_pdb.split('/')[-1],
            "Chemical": name,
            "Affinity (kcal/mol)": affinity,
            "Toxicity Risk": toxicity,
            "Stability Score": stability,
            "Docking & Mechanism": docking_raw,
            "Pathway": pathway_raw,
            "Drug Score": round(drug_score, 2)
        }

class AgentManager:
    def __init__(self, llm=None):
        self.agents: List[ProteinAgent] = []
        self.llm = llm

    def add_agent(self, protein_pdb: str) -> str:
        serial_number = f"AGENT-{len(self.agents) + 1:03d}"
        new_agent = ProteinAgent(serial_number, protein_pdb, self.llm)
        self.agents.append(new_agent)
        print(f"Added {serial_number} for protein {protein_pdb}")
        return serial_number

    def run_chemical_screening(self, csv_path: str, max_workers: int = 4) -> List[Dict[str, Any]]:
        try:
            df = pd.read_csv(csv_path)
            chemicals = df.to_dict('records')
        except Exception as e:
            print(f"Error reading CSV: {e}")
            return []

        tasks = []
        for agent in self.agents:
            for chem in chemicals:
                tasks.append((agent, chem['SMILES'], chem['Name']))

        print(f"\nStarting parallel screening with {len(tasks)} tasks...")
        results = []

        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_to_task = {
                executor.submit(agent.analyze_chemical, smiles, name): (agent.serial_number, name)
                for agent, smiles, name in tasks
            }

            for future in concurrent.futures.as_completed(future_to_task):
                agent_serial, name = future_to_task[future]
                try:
                    res = future.result()
                    results.append(res)
                except Exception as exc:
                    print(f"Task for {name} by {agent_serial} generated an exception: {exc}")

        return results
