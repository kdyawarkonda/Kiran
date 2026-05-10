import torch
from torch.utils.data import Dataset
import numpy as np

class PADDataset(Dataset):
    """
    A PyTorch Dataset for generating mock Multimodal Data for PAD Detection.
    Generates:
    - Thermal Images (2D)
    - Hyperspectral Cubes (3D)
    - Clinical Profiles (1D Tabular)
    - Labels (0 or 1 for PAD risk)
    """
    def __init__(self, num_samples=100, img_size=64, spectral_bands=16):
        super().__init__()
        self.num_samples = num_samples
        self.img_size = img_size
        self.spectral_bands = spectral_bands

        # Clinical features list:
        # [Age (norm), BMI (norm), Diabetes (0/1), Smoking (norm), Hypertension (0/1), PVD_Drug (0/1)]
        self.num_clinical_features = 6

        # Generate mock data
        self.thermal_data = self._generate_thermal_data()
        self.spectral_data = self._generate_spectral_data()
        self.clinical_data = self._generate_clinical_data()
        self.labels = self._generate_labels()

    def _generate_thermal_data(self):
        # Thermal: 1 channel, img_size x img_size
        # Shape: (num_samples, 1, H, W)
        return torch.randn(self.num_samples, 1, self.img_size, self.img_size)

    def _generate_spectral_data(self):
        # Spectral: spectral_bands channels, img_size/2 x img_size/2 (often lower res than thermal)
        # Shape: (num_samples, spectral_bands, H/2, W/2)
        h_w = self.img_size // 2
        return torch.randn(self.num_samples, self.spectral_bands, h_w, h_w)

    def _generate_clinical_data(self):
        # Clinical: 1D array of features per patient
        # Shape: (num_samples, num_clinical_features)

        clinical = torch.zeros(self.num_samples, self.num_clinical_features)

        # Age (normalized 0-1, roughly mapping 20-90 years)
        clinical[:, 0] = torch.rand(self.num_samples)

        # BMI (normalized)
        clinical[:, 1] = torch.rand(self.num_samples)

        # Diabetes (binary)
        clinical[:, 2] = torch.randint(0, 2, (self.num_samples,)).float()

        # Smoking Pack Years (normalized)
        clinical[:, 3] = torch.rand(self.num_samples)

        # Hypertension (binary)
        clinical[:, 4] = torch.randint(0, 2, (self.num_samples,)).float()

        # PVD Drug History (binary)
        clinical[:, 5] = torch.randint(0, 2, (self.num_samples,)).float()

        return clinical

    def _generate_labels(self):
        # Binary Classification: 0 (Healthy), 1 (PAD)
        # Shape: (num_samples, 1)
        return torch.randint(0, 2, (self.num_samples, 1)).float()

    def __len__(self):
        return self.num_samples

    def __getitem__(self, idx):
        thermal = self.thermal_data[idx]
        spectral = self.spectral_data[idx]
        clinical = self.clinical_data[idx]
        label = self.labels[idx]

        return {
            'thermal': thermal,
            'spectral': spectral,
            'clinical': clinical,
            'label': label
        }

if __name__ == "__main__":
    # Test the dataset
    dataset = PADDataset(num_samples=5)
    print(f"Dataset length: {len(dataset)}")
    sample = dataset[0]
    print(f"Thermal shape: {sample['thermal'].shape}")
    print(f"Spectral shape: {sample['spectral'].shape}")
    print(f"Clinical shape: {sample['clinical'].shape}")
    print(f"Label shape: {sample['label'].shape}")
    print(f"Clinical data: {sample['clinical']}")
    print(f"Label: {sample['label']}")
