import torch
from model import PADDetectionModel
import numpy as np

def run_inference():
    print("--- PAD AI Multimodal Inference Engine ---")

    # 1. Initialize Model
    model = PADDetectionModel()

    # 2. Load trained weights (if available, otherwise use initialized weights for demo)
    try:
        model.load_state_dict(torch.load("pad_ai_model.pth"))
        print("Successfully loaded trained model weights.")
    except FileNotFoundError:
        print("Warning: pad_ai_model.pth not found. Using untrained weights.")

    model.eval() # Set to evaluation mode

    # 3. Simulate Incoming Patient Data
    print("\nReceiving new patient data (Thermal, Spectral, Clinical)...")

    # Simulate a single patient (Batch Size = 1)
    # Thermal image (1, 1, 64, 64)
    incoming_thermal = torch.randn(1, 1, 64, 64)

    # Hyperspectral cube (1, 16, 32, 32)
    incoming_spectral = torch.randn(1, 16, 32, 32)

    # Clinical profile (1, 6): [Age=0.7, BMI=0.6, Diabetes=1, Smoking=0.8, Hyper=1, PVD_Drug=0]
    # Very high risk profile
    incoming_clinical = torch.tensor([[0.7, 0.6, 1.0, 0.8, 1.0, 0.0]])

    # 4. Perform Inference
    with torch.no_grad():
        risk_score = model(incoming_thermal, incoming_spectral, incoming_clinical)

    probability = risk_score.item() * 100

    # 5. Output Result
    print(f"\n--- Diagnostic Result ---")
    print(f"Patient PAD Risk Probability: {probability:.2f}%")

    if probability > 50.0:
        print("Recommendation: HIGH RISK FLAG.")
        print("Action: Schedule patient for Ankle-Brachial Index (ABI) test and vascular consult.")
    else:
        print("Recommendation: LOW RISK.")
        print("Action: Continue standard preventative care.")

if __name__ == "__main__":
    run_inference()
