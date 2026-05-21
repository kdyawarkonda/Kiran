#!/bin/bash

# Exit on error
set -e

echo "Starting model and dependency installation for Cardiac Fibrosis Drug Discovery Pipeline..."

# 1. Install system dependencies (assuming Debian/Ubuntu based for local execution)
echo "Installing system dependencies..."
sudo apt-get update -y || echo "Skipping apt update..."
sudo apt-get install -y git wget curl build-essential || echo "Skipping apt install..."

# 2. Install Python packages
echo "Installing Python dependencies from requirements.txt..."
pip install -r requirements.txt || echo "Make sure you are in an active virtual environment."

# 3. Create directories for models
echo "Creating directories for specific models..."
mkdir -p models/DiffDock
mkdir -p models/Graphormer
mkdir -p models/DiffusionGenerator

# 4. Pulling DiffDock
echo "Setting up DiffDock..."
if [ ! -d "models/DiffDock/.git" ]; then
    git clone https://github.com/gcorso/DiffDock.git models/DiffDock
else
    echo "DiffDock already exists."
fi

# 5. Setting up ESM2 (HuggingFace Transformers will handle weights automatically,
# but ensuring the cache directory is established)
export HF_HOME="./models/huggingface_cache"
echo "HuggingFace cache set to $HF_HOME for ESM2."

# 6. Note on AlphaFold3
echo "Note: AlphaFold3 requires significant infrastructure.
The pipeline script will be configured to either use the API or local wrappers based on your setup."

# 7. Note on OpenMM and PySCF
echo "OpenMM and PySCF installed via pip for Quantum Refinement and Molecular Dynamics."

echo "Installation setup complete. You may now run pipeline.py"
