import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader
from dataset import PADDataset
from model import PADDetectionModel
import numpy as np
from sklearn.metrics import accuracy_score, roc_auc_score

def train_model():
    print("--- Initializing PAD Multimodal AI Training Pipeline ---")

    # Hyperparameters
    batch_size = 16
    epochs = 5
    learning_rate = 0.001

    # 1. Load Data
    print("Generating synthetic datasets...")
    train_dataset = PADDataset(num_samples=200)
    val_dataset = PADDataset(num_samples=50)

    train_loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True)
    val_loader = DataLoader(val_dataset, batch_size=batch_size, shuffle=False)

    # 2. Initialize Model, Loss, Optimizer
    model = PADDetectionModel()
    criterion = nn.BCELoss() # Binary Cross Entropy for 0/1 prediction
    optimizer = optim.Adam(model.parameters(), lr=learning_rate)

    print("Starting training loop...\n")
    for epoch in range(epochs):
        model.train()
        train_loss = 0.0

        # Training loop
        for batch in train_loader:
            thermal = batch['thermal']
            spectral = batch['spectral']
            clinical = batch['clinical']
            labels = batch['label']

            # Zero gradients
            optimizer.zero_grad()

            # Forward pass
            outputs = model(thermal, spectral, clinical)
            loss = criterion(outputs, labels)

            # Backward pass & Optimize
            loss.backward()
            optimizer.step()

            train_loss += loss.item() * thermal.size(0)

        train_loss = train_loss / len(train_loader.dataset)

        # Validation loop
        model.eval()
        val_loss = 0.0
        all_labels = []
        all_preds = []

        with torch.no_grad():
            for batch in val_loader:
                thermal = batch['thermal']
                spectral = batch['spectral']
                clinical = batch['clinical']
                labels = batch['label']

                outputs = model(thermal, spectral, clinical)
                loss = criterion(outputs, labels)
                val_loss += loss.item() * thermal.size(0)

                # Store for metrics
                all_labels.extend(labels.numpy())
                all_preds.extend(outputs.numpy())

        val_loss = val_loss / len(val_loader.dataset)

        # Calculate Metrics
        all_labels = np.array(all_labels)
        all_preds = np.array(all_preds)
        binary_preds = (all_preds >= 0.5).astype(int)

        accuracy = accuracy_score(all_labels, binary_preds)

        try:
            # AUC can fail if the mock dataset generates only 1 class in the batch
            auc = roc_auc_score(all_labels, all_preds)
        except ValueError:
            auc = 0.5

        print(f"Epoch [{epoch+1}/{epochs}] | Train Loss: {train_loss:.4f} | Val Loss: {val_loss:.4f} | Val Acc: {accuracy:.4f} | Val AUC: {auc:.4f}")

    # Save the trained model
    torch.save(model.state_dict(), "pad_ai_model.pth")
    print("\nTraining complete. Model saved to pad_ai_model.pth")

if __name__ == "__main__":
    train_model()
