import torch
from torch.utils.data import Dataset
import numpy as np
import os
from PIL import Image
import torchvision.transforms as transforms

class PADDataset(Dataset):
    """
    A PyTorch Dataset for loading Multimodal Data for PAD Detection.
    Now supports loading REAL thermal images from disk!
    - Thermal Images: Loaded from disk (PNG/JPG)
    - Hyperspectral Cubes: Generated mock data (until real datasets are available)
    - Clinical Profiles: Generated mock data
    """
    def __init__(self, data_dir=None, split='train', num_samples=100, img_size=64, spectral_bands=16):
        super().__init__()
        self.data_dir = data_dir
        self.split = split
        self.img_size = img_size
        self.spectral_bands = spectral_bands

        self.num_clinical_features = 6

        # Determine how to load thermal data
        self.use_real_images = False
        self.image_paths = []
        self.labels = []

        if self.data_dir and os.path.exists(os.path.join(self.data_dir, self.split)):
            self.use_real_images = True
            split_dir = os.path.join(self.data_dir, self.split)

            # Load paths for healthy (label 0)
            healthy_dir = os.path.join(split_dir, 'healthy')
            if os.path.exists(healthy_dir):
                for img_name in os.listdir(healthy_dir):
                    self.image_paths.append(os.path.join(healthy_dir, img_name))
                    self.labels.append(0.0)

            # Load paths for pad_risk (label 1)
            risk_dir = os.path.join(split_dir, 'pad_risk')
            if os.path.exists(risk_dir):
                for img_name in os.listdir(risk_dir):
                    self.image_paths.append(os.path.join(risk_dir, img_name))
                    self.labels.append(1.0)

            self.num_samples = len(self.image_paths)
            print(f"Loaded {self.num_samples} real thermal images from {split_dir}")
        else:
            self.num_samples = num_samples
            print(f"No real data directory found. Using {self.num_samples} mock samples.")
            self.labels = self._generate_mock_labels()

        # Image transforms
        self.transform = transforms.Compose([
            transforms.Resize((self.img_size, self.img_size)),
            transforms.ToTensor(), # Converts to [0, 1] and adds channel dim
            transforms.Normalize(mean=[0.5], std=[0.5])
        ])

        # Generate mock data for the branches we don't have files for yet
        self.spectral_data = self._generate_spectral_data()
        self.clinical_data = self._generate_clinical_data()

    def _generate_mock_labels(self):
        return torch.randint(0, 2, (self.num_samples, 1)).float().flatten().tolist()

    def _generate_spectral_data(self):
        h_w = self.img_size // 2
        return torch.randn(self.num_samples, self.spectral_bands, h_w, h_w)

    def _generate_clinical_data(self):
        clinical = torch.zeros(self.num_samples, self.num_clinical_features)
        clinical[:, 0] = torch.rand(self.num_samples) # Age
        clinical[:, 1] = torch.rand(self.num_samples) # BMI
        clinical[:, 2] = torch.randint(0, 2, (self.num_samples,)).float() # Diabetes
        clinical[:, 3] = torch.rand(self.num_samples) # Smoking
        clinical[:, 4] = torch.randint(0, 2, (self.num_samples,)).float() # Hyper
        clinical[:, 5] = torch.randint(0, 2, (self.num_samples,)).float() # Drugs
        return clinical

    def __len__(self):
        return self.num_samples

    def __getitem__(self, idx):
        # 1. Load Thermal Data
        if self.use_real_images:
            img_path = self.image_paths[idx]
            # Convert to grayscale (1 channel) thermal representation
            img = Image.open(img_path).convert('L')
            thermal = self.transform(img)
        else:
            thermal = torch.randn(1, self.img_size, self.img_size)

        # 2. Load other branches
        spectral = self.spectral_data[idx]
        clinical = self.clinical_data[idx]

        # 3. Label
        label = torch.tensor([self.labels[idx]], dtype=torch.float32)

        return {
            'thermal': thermal,
            'spectral': spectral,
            'clinical': clinical,
            'label': label
        }

if __name__ == "__main__":
    # Test the updated dataset pointing to our generated 'data' directory
    dataset = PADDataset(data_dir="data", split="train")
    print(f"Dataset length: {len(dataset)}")
    if len(dataset) > 0:
        sample = dataset[0]
        print(f"Thermal shape: {sample['thermal'].shape}")
        print(f"Label: {sample['label']}")
