import torch
import torch.nn as nn

class ThermalBranch(nn.Module):
    """
    Analyzes 2D Thermal Maps (Thermodynamics)
    Looks for spatial temperature gradients and cold spots indicating macro-vascular blockages.
    """
    def __init__(self, in_channels=1, output_dim=64):
        super().__init__()
        self.conv_layers = nn.Sequential(
            nn.Conv2d(in_channels, 16, kernel_size=3, padding=1),
            nn.ReLU(),
            nn.MaxPool2d(2),

            nn.Conv2d(16, 32, kernel_size=3, padding=1),
            nn.ReLU(),
            nn.MaxPool2d(2),

            nn.Conv2d(32, 64, kernel_size=3, padding=1),
            nn.ReLU(),
            nn.AdaptiveAvgPool2d((1, 1)) # Flattens to (Batch, 64, 1, 1)
        )
        self.fc = nn.Linear(64, output_dim)

    def forward(self, x):
        # x shape: (Batch, 1, 64, 64)
        x = self.conv_layers(x)
        x = x.view(x.size(0), -1) # Flatten
        return self.fc(x)

class SpectralBranch(nn.Module):
    """
    Analyzes 3D Hyperspectral Cubes (Tissue Oxygenation)
    Looks at HbO2/HbR ratios to detect micro-vascular perfusion loss.
    Uses 2D Convolutions applied across the wavelength dimension.
    """
    def __init__(self, in_channels=16, output_dim=64):
        super().__init__()
        self.conv_layers = nn.Sequential(
            nn.Conv2d(in_channels, 32, kernel_size=3, padding=1),
            nn.ReLU(),
            nn.MaxPool2d(2),

            nn.Conv2d(32, 64, kernel_size=3, padding=1),
            nn.ReLU(),
            nn.AdaptiveAvgPool2d((1, 1))
        )
        self.fc = nn.Linear(64, output_dim)

    def forward(self, x):
        # x shape: (Batch, 16, 32, 32)
        x = self.conv_layers(x)
        x = x.view(x.size(0), -1)
        return self.fc(x)

class ClinicalBranch(nn.Module):
    """
    Analyzes 1D Tabular Patient Profiles
    Extracts patterns from age, smoking history, diabetes, etc.
    """
    def __init__(self, num_features=6, output_dim=32):
        super().__init__()
        self.mlp = nn.Sequential(
            nn.Linear(num_features, 16),
            nn.ReLU(),
            nn.Linear(16, output_dim),
            nn.ReLU()
        )

    def forward(self, x):
        # x shape: (Batch, 6)
        return self.mlp(x)

class PADDetectionModel(nn.Module):
    """
    Multimodal Tri-Branch Fusion Network for PAD Detection
    Combines Thermodynamics, Hyperspectroscopy, and Clinical Data.
    """
    def __init__(self, clinical_features=6):
        super().__init__()

        # Dimensions for the latent vectors from each branch
        self.thermal_dim = 64
        self.spectral_dim = 64
        self.clinical_dim = 32

        # Initialize Branches
        self.thermal_branch = ThermalBranch(in_channels=1, output_dim=self.thermal_dim)
        self.spectral_branch = SpectralBranch(in_channels=16, output_dim=self.spectral_dim)
        self.clinical_branch = ClinicalBranch(num_features=clinical_features, output_dim=self.clinical_dim)

        # Fusion Layer
        fusion_dim = self.thermal_dim + self.spectral_dim + self.clinical_dim

        self.classifier = nn.Sequential(
            nn.Linear(fusion_dim, 64),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.Linear(64, 1),
            nn.Sigmoid() # Outputs a probability score from 0.0 to 1.0
        )

    def forward(self, thermal, spectral, clinical):
        # 1. Extract features from each branch
        therm_features = self.thermal_branch(thermal)
        spec_features = self.spectral_branch(spectral)
        clin_features = self.clinical_branch(clinical)

        # 2. Early Fusion: Concatenate the feature vectors
        fused = torch.cat((therm_features, spec_features, clin_features), dim=1)

        # 3. Predict Risk Score
        risk_score = self.classifier(fused)

        return risk_score

if __name__ == "__main__":
    # Test the model with dummy tensors
    model = PADDetectionModel()

    dummy_thermal = torch.randn(2, 1, 64, 64) # Batch size 2
    dummy_spectral = torch.randn(2, 16, 32, 32)
    dummy_clinical = torch.randn(2, 6)

    out = model(dummy_thermal, dummy_spectral, dummy_clinical)

    print("Model architecture compiled successfully.")
    print(f"Output shape (Batch Size, 1): {out.shape}")
    print(f"Sample Output Probabilities:\n{out.detach().numpy()}")
