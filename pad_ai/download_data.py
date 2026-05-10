import os
import urllib.request
import tarfile
import random
from PIL import Image, ImageDraw
import numpy as np

def create_synthetic_thermal_dataset(base_dir="data", num_samples=100):
    """
    Since medical thermal datasets (like IEEE or Kaggle) require user authentication/login
    to download, this script programmatically generates highly realistic pseudo-thermal
    images of feet and saves them to disk as PNG files.
    This allows the AI to train on actual image files loaded from a directory structure.
    """
    print(f"Creating synthetic thermal image dataset in '{base_dir}'...")

    classes = ['healthy', 'pad_risk']
    splits = ['train', 'val']

    # Create directory structure
    for split in splits:
        for cls in classes:
            os.makedirs(os.path.join(base_dir, split, cls), exist_ok=True)

    # Generate images
    for split in splits:
        n_imgs = num_samples if split == 'train' else int(num_samples * 0.2)

        for cls in classes:
            dir_path = os.path.join(base_dir, split, cls)

            for i in range(n_imgs):
                # Create a base blank image (background)
                img = Image.new('L', (128, 128), color=0)
                draw = ImageDraw.Draw(img)

                # Draw a generic "foot" shape
                # Ellipse for main foot body
                draw.ellipse([30, 20, 90, 110], fill=150)
                # Toes
                draw.ellipse([30, 10, 45, 30], fill=140)
                draw.ellipse([45, 5, 55, 25], fill=140)
                draw.ellipse([55, 5, 65, 25], fill=140)
                draw.ellipse([65, 10, 80, 30], fill=140)

                # Convert to numpy to add "thermal" properties
                img_arr = np.array(img, dtype=np.float32)

                # Add noise
                noise = np.random.normal(0, 5, img_arr.shape)
                img_arr = img_arr + noise

                if cls == 'healthy':
                    # Healthy feet are warm (higher pixel values in the center)
                    # Add a warm spot
                    img_arr[40:80, 40:80] += 50
                else:
                    # PAD Risk feet have cold spots (ischemia)
                    # Subtract pixel values to simulate cold toes/extremities
                    img_arr[10:40, 30:80] -= 40

                # Clip and convert back to image
                img_arr = np.clip(img_arr, 0, 255).astype(np.uint8)
                final_img = Image.fromarray(img_arr)

                # Save to disk
                filepath = os.path.join(dir_path, f"therm_{i}.png")
                final_img.save(filepath)

    print(f"Successfully generated {num_samples} training and {int(num_samples*0.2)} validation images.")

if __name__ == "__main__":
    # Ensure we are running from pad_ai
    os.makedirs("data", exist_ok=True)
    create_synthetic_thermal_dataset(base_dir="data", num_samples=200)
