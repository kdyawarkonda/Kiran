import concurrent.futures
import pandas as pd
from typing import List, Dict, Any
from langchain.agents import initialize_agent, AgentType
from langchain_community.chat_models import ChatOpenAI
# Alternatively, use a local open-source model to reduce token cost
# from langchain_community.llms import LlamaCpp

from .tools import analyze_stability, analyze_efficacy, analyze_side_effects, find_biological_pathways

class ProteinAgent:
    def __init__(self, serial_number: str, protein_pdb: str, llm=None):
        self.serial_number = serial_number
        self.protein_pdb = protein_pdb

        # We use a placeholder for the LLM if none is provided.
        if llm is None:
            self.llm = None
        else:
            self.llm = llm

        self.tools = [
            analyze_stability,
            analyze_efficacy,
            analyze_side_effects,
            find_biological_pathways
        ]

        # Initialize the LangChain Agent using the older, more compatible method
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

    def analyze_chemical(self, smiles: str, name: str) -> Dict[str, Any]:
        """
        Runs the agent on a single chemical to find if it is a suitable inhibitor.
        """
        prompt = f"""
        You are Agent {self.serial_number}, an expert in pharmaceutical chemistry and quantum-enhanced models.
        Your task is to analyze the chemical '{name}' (SMILES: {smiles}) as an inhibitor for the protein variant found in {self.protein_pdb}.

        Use your tools to find:
        1. The binding efficacy of the chemical to the protein. When using the efficacy tool, format the input as: {smiles},{self.protein_pdb}
        2. The biological pathways it affects.
        3. The side effect profile.
        4. The environmental stability of the chemical.

        Summarize your findings. Keep it concise to save tokens.
        """

        try:
            if self.agent:
                result = self.agent.run(prompt)
            else:
                # Fallback if LLM is not configured
                result = "LLM not configured. Manual tool execution simulated."
                result += f"\n- {analyze_efficacy.invoke(f'{smiles},{self.protein_pdb}')}"
                result += f"\n- {find_biological_pathways.invoke(smiles)}"
                result += f"\n- {analyze_side_effects.invoke(smiles)}"
                result += f"\n- {analyze_stability.invoke(smiles)}"

        except Exception as e:
            result = f"Error during analysis: {str(e)}"

        return {
            "agent_serial": self.serial_number,
            "chemical_name": name,
            "smiles": smiles,
            "analysis_result": result
        }

class AgentManager:
    def __init__(self, llm=None):
        self.agents: List[ProteinAgent] = []
        self.llm = llm

    def add_agent(self, protein_pdb: str) -> str:
        """
        Creates a new agent for a specific protein variant and assigns a serial number.
        """
        serial_number = f"AGENT-{len(self.agents) + 1:03d}"
        new_agent = ProteinAgent(serial_number, protein_pdb, self.llm)
        self.agents.append(new_agent)
        print(f"Added {serial_number} for protein {protein_pdb}")
        return serial_number

    def run_chemical_screening(self, csv_path: str, max_workers: int = 4) -> List[Dict[str, Any]]:
        """
        Runs the chemical screening process across all agents and all chemicals in the CSV.
        Executes in parallel using ThreadPoolExecutor.
        """
        try:
            df = pd.read_csv(csv_path)
            chemicals = df.to_dict('records')
        except Exception as e:
            print(f"Error reading CSV: {e}")
            return []

        tasks = []
        # Create a task for every combination of Agent and Chemical
        for agent in self.agents:
            for chem in chemicals:
                tasks.append((agent, chem['SMILES'], chem['Name']))

        print(f"Starting parallel screening with {len(tasks)} tasks...")
        results = []

        # Run tasks in parallel
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
                    print(f"Completed analysis for {name} by {agent_serial}")
                except Exception as exc:
                    print(f"Task for {name} by {agent_serial} generated an exception: {exc}")

        return results
