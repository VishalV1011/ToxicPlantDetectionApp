import os
import json
import io
import numpy as np
import tensorflow as tf
from PIL import Image, ImageOps
from flask import Flask, jsonify, request
import requests
import firebase_admin
from firebase_admin import credentials, firestore

app = Flask(__name__)

# --- 1. CONFIGURATION ---
PERENUAL_API_KEY = "sk-tiQN690a1efb6d2a713302"
PERENUAL_BASE_URL = "https://perenual.com/api/species-list"

# --- 2. FIREBASE CONNECTION ---
if not firebase_admin._apps:
    try:
        cred = credentials.Certificate("credentials.json")
        firebase_admin.initialize_app(cred)
        db = firestore.client()
        print("✅ Connected to Firebase")
    except Exception as e:
        print(f"🔥 Firebase error: {e}")
        db = None
else:
    db = firestore.client()

# --- 3. LOAD AI MODEL ---
print("⏳ Loading AI Model...")

def custom_preprocess(x):
    return x

try:
    with open("config.json", "r") as json_file:
        json_config = json_file.read()
    
    model = tf.keras.models.model_from_json(
        json_config,
        custom_objects={'preprocess_input': custom_preprocess} 
    )
    model.load_weights("model.weights.h5")

    # ⚠️ YOUR CORRECT CLASS LIST FROM GRADIO
    CLASS_NAMES = [
        'Abrus precatorius', 'Acalypha indica', 'Anacardium occidentale',
        'Annona_muricata', 'Annona_squamosa', 'Aristolochia tagala',
        'Asthma-plant (Euphorbia hirta)', 'Ayushvision_flowers',
        'Blind-your-eye Mangrove (Excoecaria agallocha)', 'Cerbera_odollam',
        'Clerodendrum inerme', 'Croton tiglium',
        'Devil backbone(euphorbia tithymaloides)', 'Dioscorea hispida Dennst',
        'Euphorbia Milli', 'Heart of Jesus (caladium bicolor)',
        'Kigelia_africana', 'Oleander', 'Pencil tree (euphorbia tirucalli)',
        'Phytolacca_octandra', 'Poisonous American Mushrooms',
        'Senna Alata', 'Solanum nigrum', 'Sterculia_foetida',
        'Strychnos_nux-vomica', 'adenium obesum', 'aloe vera',
        'heliconia rostrata', 'poisen ivy', 'wild gooseberry'
    ]
    print(f"✅ Model Loaded with {len(CLASS_NAMES)} classes.")

except Exception as e:
    print(f"❌ CRITICAL ERROR LOADING MODEL: {e}")
    model = None
    CLASS_NAMES = []

# --- 4. DATABASE SEARCH HELPER ---
def search_database(predicted_label):
    final_response = {}
    
    # Clean the messy Gradio name to match clean Firebase IDs
    clean_id = predicted_label.lower().strip()
    if '(' in clean_id: # Remove parens like "Heart of Jesus (caladium...)"
        try: clean_id = clean_id[clean_id.find('(')+1:clean_id.find(')')]
        except: pass
    clean_id = clean_id.replace(" ", "_")

    if db:
        doc = db.collection('plants').document(clean_id).get()
        if doc.exists:
            final_response = doc.to_dict()
            final_response['source'] = "Curated Database"

    if not final_response:
        # Fallback to API if not in Firebase
        try:
            params = {'key': PERENUAL_API_KEY, 'q': clean_id.replace("_", " ")}
            resp = requests.get(PERENUAL_BASE_URL, params=params).json()
            if resp.get('data'):
                final_response = {
                    "scientific_name": resp['data'][0].get('scientific_name', [predicted_label])[0],
                    "common_name": resp['data'][0].get('common_name', predicted_label),
                    "is_toxic": True,
                    "symptoms": "Identified as toxic. Details pending.",
                    "poisoning_action": "Seek medical help.",
                    "source": "Perenual API"
                }
                if resp['data'][0].get('default_image'):
                    final_response['image_url'] = resp['data'][0]['default_image'].get('regular_url')
        except: pass

    if not final_response:
        final_response = {
            "scientific_name": predicted_label,
            "common_name": predicted_label,
            "is_toxic": True,
            "symptoms": "Caution advised.",
            "poisoning_action": "Avoid ingestion.",
            "source": "AI Prediction"
        }
    return final_response

# --- 5. THE "BRUTE FORCE" PREDICTOR ---
@app.route("/predict", methods=["POST"])
def predict():
    if not model: return jsonify({"error": "Model not loaded"}), 500
    if 'file' not in request.files: return jsonify({"error": "No file uploaded"}), 400
    
    try:
        # 1. Prepare Base Image
        file = request.files['file']
        image = Image.open(io.BytesIO(file.read()))
        image = ImageOps.exif_transpose(image) # Fix rotation
        if image.mode != 'RGB': image = image.convert('RGB')
        image = image.resize((224, 224), Image.Resampling.LANCZOS)
        
        # 2. CREATE 4 DIFFERENT VERSIONS (The "Skeleton Key")
        img_array = np.array(image, dtype=np.float32)
        
        candidates = {}
        
        # Mode A: RAW [0, 255] (Common for EfficientNet / ResNetV2)
        candidates['Raw [0-255]'] = np.expand_dims(img_array, axis=0)
        
        # Mode B: NORMALIZED [0, 1] (Common for custom CNNs)
        candidates['Normalized [0-1]'] = np.expand_dims(img_array / 255.0, axis=0)
        
        # Mode C: CENTERED [-1, 1] (Standard for MobileNetV2)
        candidates['Centered [-1 to 1]'] = np.expand_dims((img_array / 127.5) - 1.0, axis=0)
        
        # Mode D: CAFFE [BGR, Unscaled] (Standard for ResNet50 / VGG)
        # Convert RGB to BGR, then subtract mean
        img_bgr = img_array[..., ::-1] 
        mean = [103.939, 116.779, 123.68]
        img_caffe = img_bgr - mean
        candidates['Caffe Style'] = np.expand_dims(img_caffe, axis=0)

        # 3. TEST ALL 4
        best_conf = -1.0
        best_mode = "None"
        best_idx = 0
        
        print("\n--- 🧪 DIAGNOSTIC TEST ---")
        for mode_name, input_data in candidates.items():
            preds = model.predict(input_data, verbose=0)
            conf = float(np.max(preds))
            idx = np.argmax(preds)
            plant = CLASS_NAMES[idx] if idx < len(CLASS_NAMES) else "Unknown"
            
            print(f"Trying {mode_name}: Confidence = {conf:.4f} -> {plant}")
            
            if conf > best_conf:
                best_conf = conf
                best_mode = mode_name
                best_idx = idx

        # 4. PICK WINNER
        print(f"🏆 WINNER: {best_mode} with {best_conf:.2f} confidence")
        
        # Map to Name
        if 0 <= best_idx < len(CLASS_NAMES):
            plant_name = CLASS_NAMES[best_idx]
        else:
            plant_name = "Unknown Index"

        # 5. Get Details
        details = search_database(plant_name)
        details['predicted_name'] = plant_name
        details['confidence'] = best_conf
        
        return jsonify(details)

    except Exception as e:
        print(f"🔥 SERVER ERROR: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)