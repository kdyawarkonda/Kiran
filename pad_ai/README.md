# Multimodal AI for Early Detection of Peripheral Arterial Disease (PAD)

This repository contains the architecture and scaffolding for an advanced, multimodal artificial intelligence system designed to detect Peripheral Arterial Disease (PAD) *before* the onset of physical symptoms (like intermittent claudication).

## Architecture Overview

This AI uses a **Tri-Branch Fusion Neural Network** to simultaneously process three distinct types of patient data:

1. **Thermodynamics (Thermal Imaging):**
   - A 2D Convolutional Neural Network (CNN) analyzes thermal gradients to detect macro-vascular temperature anomalies (cold spots indicating lack of blood flow).
2. **Hyperspectroscopy (Tissue Oxygenation):**
   - A 3D/Spatial-Spectral CNN analyzes hyperspectral data cubes to measure the ratio of oxygenated to deoxygenated hemoglobin, identifying micro-vascular perfusion loss.
3. **Clinical Profile (EHR Data):**
   - A Multi-Layer Perceptron (MLP) analyzes tabular patient risk factors including age, BMI, diabetes status, smoking history, hypertension, and PVD drug usage.

The latent features from all three branches are concatenated (Early Fusion) and passed through a classification head to output a final PAD Risk Probability (0.0 to 1.0).

## Files

- `dataset.py`: Contains a PyTorch `Dataset` that generates synthetic (mock) thermal, spectral, and clinical data for testing the architecture.
- `model.py`: The core PyTorch code containing the `PADDetectionModel` and its three constituent branches.
- `train.py`: The training loop. Loads data, calculates Binary Cross Entropy loss, backpropagates using Adam optimizer, and tracks validation metrics.
- `predict.py`: Inference engine. Loads a trained `.pth` model, simulates an incoming patient scan, and outputs a diagnostic recommendation.
- `requirements.txt`: Required Python dependencies.

## Installation

```bash
pip install -r requirements.txt
```

## Usage

**1. Train the Model**
Run the training pipeline. This will train on the mock data and generate a `pad_ai_model.pth` weights file.
```bash
python3 train.py
```

**2. Run Inference**
Test the model on a simulated patient to get a diagnostic recommendation.
```bash
python3 predict.py
```

## Future Work
- Replace mock data generation with a real clinical dataset loading pipeline (e.g., from DICOM or NIfTI files).
- Implement Grad-CAM in `predict.py` to output visual heatmaps explaining *why* the AI flagged specific regions in the thermal/spectral images.
