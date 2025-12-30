import os
import json
import io
import numpy as np
import pandas as pd
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
CSV_PATH = 'toxic_plants.csv' # Ensure this file is in the same folder

# Global Database Cache
plant_database = {}

# --- 2. LOAD LOCAL CSV DATABASE ---
# This loads your CSV into memory for instant O(1) lookup
def load_csv_database():
    global plant_database
    try:
        if os.path.exists(CSV_PATH):
            df = pd.read_csv(CSV_PATH)
            # Clean column names
            df.columns = [c.strip().lower() for c in df.columns]
            
            # Build dictionary: Key = Scientific Name (lowercase)
            for _, row in df.iterrows():
                # Adjust these keys if your CSV headers are slightly different
                sci_name = str(row.get('scientific name', '')).strip().lower()
                
                if sci_name:
                    plant_database[sci_name] = {
                        'common_name': row.get('common name', 'Unknown'),
                        'scientific_name': row.get('scientific name', 'Unknown'),
                        # Basic logic to determine if toxic based on level string
                        'is_toxic': 'non-toxic' not in str(row.get('toxicity level', '')).lower(),
                        'symptoms': row.get('symptoms', 'No information available.'),
                        'poisoning_action': row.get('treatment/action', 'Consult a professional.'),
                        'source': "Local CSV Database"
                    }
            print(f"✅ CSV Database Loaded: {len(plant_database)} plants.")
        else:
            print(f"⚠️ Warning: {CSV_PATH} not found. Using Fallbacks only.")
    except Exception as e:
        print(f"❌ Error loading CSV: {e}")

load_csv_database()

# --- 3. FIREBASE CONNECTION ---
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

# --- 4. LOAD AI MODEL ---
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

# --- 5. DATABASE SEARCH HELPER (UPDATED) ---
def search_database(predicted_label):
    final_response = {}
    
    # 1. Clean the ID for matching
    clean_id = predicted_label.lower().strip()
    if '(' in clean_id: # Remove parens
        try: clean_id = clean_id[clean_id.find('(')+1:clean_id.find(')')]
        except: pass
    
    # Clean ID for Firebase/API (underscores -> spaces or vice versa)
    search_term = clean_id.replace("_", " ").strip()
    
    # --- LEVEL 1: CHECK LOCAL CSV (Fastest & Most Accurate) ---
    # We try exact match first, then partial match
    if search_term in plant_database:
        return plant_database[search_term]
    
    # Fallback: Check if search_term is inside any key in the CSV
    for key in plant_database:
        if search_term in key or key in search_term:
            return plant_database[key]

    # --- LEVEL 2: FIREBASE ---
    clean_id_fb = clean_id.replace(" ", "_")
    if db:
        doc = db.collection('plants').document(clean_id_fb).get()
        if doc.exists:
            final_response = doc.to_dict()
            final_response['source'] = "Firebase Database"
            return final_response

    # --- LEVEL 3: EXTERNAL API (Perenual) ---
    try:
        params = {'key': PERENUAL_API_KEY, 'q': search_term}
        resp = requests.get(PERENUAL_BASE_URL, params=params).json()
        if resp.get('data'):
            data = resp['data'][0]
            final_response = {
                "scientific_name": data.get('scientific_name', [predicted_label])[0],
                "common_name": data.get('common_name', predicted_label),
                "is_toxic": True, # Assume toxic if identified by this specific app
                "symptoms": "Identified as toxic. Details pending.",
                "poisoning_action": "Seek medical help immediately.",
                "source": "Perenual API"
            }
            if data.get('default_image'):
                final_response['image_url'] = data['default_image'].get('regular_url')
            return final_response
    except: pass

    # --- LEVEL 4: FALLBACK ---
    return {
        "scientific_name": predicted_label,
        "common_name": predicted_label,
        "is_toxic": True,
        "symptoms": "Caution advised.",
        "poisoning_action": "Avoid ingestion.",
        "source": "AI Prediction Only"
    }

# --- 6. THE "BRUTE FORCE" PREDICTOR ---
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
        
        # Mode A: RAW [0, 255]
        candidates['Raw [0-255]'] = np.expand_dims(img_array, axis=0)
        
        # Mode B: NORMALIZED [0, 1]
        candidates['Normalized [0-1]'] = np.expand_dims(img_array / 255.0, axis=0)
        
        # Mode C: CENTERED [-1, 1]
        candidates['Centered [-1 to 1]'] = np.expand_dims((img_array / 127.5) - 1.0, axis=0)
        
        # Mode D: CAFFE [BGR, Unscaled]
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

        # 5. Get Details (Now checks CSV first!)
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