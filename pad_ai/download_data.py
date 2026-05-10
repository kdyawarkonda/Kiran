import os
import shutil
import kagglehub

def download_and_organize_dataset():
    print("Downloading the Kaggle dataset 'Thermography images of diabetic foot'...")

    # Download latest version
    download_path = kagglehub.dataset_download("vuppalaadithyasairam/thermography-images-of-diabetic-foot")
    print(f"Dataset downloaded to: {download_path}")

    # Organize into our expected structure: data/train/healthy/ and data/train/pad_risk/
    # The Kaggle dataset structure needs to be mapped.
    # Typically, datasets have class folders inside. Let's see what's in there.

    base_dir = "data"
    train_dir = os.path.join(base_dir, "train")
    val_dir = os.path.join(base_dir, "val")

    # We will clear out the existing synthetic data
    if os.path.exists(base_dir):
        print(f"Cleaning up existing '{base_dir}' directory...")
        shutil.rmtree(base_dir)

    os.makedirs(os.path.join(train_dir, "healthy"), exist_ok=True)
    os.makedirs(os.path.join(train_dir, "pad_risk"), exist_ok=True)
    os.makedirs(os.path.join(val_dir, "healthy"), exist_ok=True)
    os.makedirs(os.path.join(val_dir, "pad_risk"), exist_ok=True)

    print("Organizing dataset...")

    # Let's inspect the downloaded path to see how the Kaggle user structured it
    # Usually it's either unzipped directly or in subfolders like "Normal" and "Diabetic"

    # Helper to recursively find image files and their parent directories
    all_images = []
    for root, _, files in os.walk(download_path):
        for file in files:
            if file.lower().endswith(('.png', '.jpg', '.jpeg')):
                all_images.append(os.path.join(root, file))

    if not all_images:
        print("No images found in the downloaded dataset.")
        return

    # We need to map the Kaggle dataset's class names to our 'healthy' and 'pad_risk'
    healthy_count = 0
    risk_count = 0

    # We'll put 80% in train, 20% in val
    for img_path in all_images:
        path_lower = img_path.lower()
        # Guess the class based on the folder or file name
        # Common class names for this dataset: 'Normal', 'Control' vs 'Diabetic', 'DFU', 'Abnormal'
        if 'normal' in path_lower or 'control' in path_lower:
            target_class = 'healthy'
        elif 'diabet' in path_lower or 'dfu' in path_lower or 'ulcer' in path_lower or 'abnormal' in path_lower:
            target_class = 'pad_risk'
        else:
            # If we can't figure it out, skip or default to healthy
            continue

        # 80/20 train/val split based on a simple counter/hash
        is_val = (healthy_count + risk_count) % 5 == 0

        if target_class == 'healthy':
            dest_dir = os.path.join(val_dir if is_val else train_dir, "healthy")
            shutil.copy2(img_path, os.path.join(dest_dir, os.path.basename(img_path)))
            healthy_count += 1
        else:
            dest_dir = os.path.join(val_dir if is_val else train_dir, "pad_risk")
            shutil.copy2(img_path, os.path.join(dest_dir, os.path.basename(img_path)))
            risk_count += 1

    print(f"Dataset organization complete!")
    print(f"Total Healthy samples: {healthy_count}")
    print(f"Total PAD Risk samples: {risk_count}")

if __name__ == "__main__":
    download_and_organize_dataset()
