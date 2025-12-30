import os
import csv
import json
import io
import gc  # Garbage Collector
import numpy as np
import tensorflow as tf
from PIL import Image, ImageOps
from flask import Flask, jsonify, request
import requests
import firebase_admin
from firebase_admin import credentials, firestore

app = Flask(__name__)

# --- CONFIGURATION ---
PERENUAL_API_KEY = "sk-tiQN690a1efb6d2a713302"
PERENUAL_BASE_URL = "https://perenual.com/api/species-list"
CSV_PATH = 'toxic_plants.csv'

# Global Database Cache
plant_database = {}

# --- 1. LIGHTWEIGHT CSV LOADER (No Pandas) ---
def load_csv_database():
    global plant_database
    try:
        if os.path.exists(CSV_PATH):
            # Use standard CSV library instead of Pandas to save RAM
            with open(CSV_PATH, mode='r', encoding='utf-8-sig') as f:
                reader = csv.DictReader(f)
                
                # Normalize headers to lowercase/stripped
                reader.fieldnames = [name.strip().lower() for name in reader.fieldnames]
                
                for row in reader:
                    # Adjust 'scientific name' if your CSV header is different
                    sci_name = row.get('scientific name', '').strip().lower()
                    
                    if sci_name:
                        plant_database[sci_name] = {
                            'common_name': row.get('common name', 'Unknown'),
                            'scientific_name': row.get('scientific name', 'Unknown'),
                            'is_toxic': 'non-toxic' not in row.get('toxicity level', '').lower(),
                            'symptoms': row.get('symptoms', 'No info available.'),
                            'poisoning_action': row.get('treatment/action', 'Consult a professional.'),
                            'source': "Local CSV Database"
                        }
            print(f"✅ CSV Database Loaded: {len(plant_database)} plants.")
        else:
            print(f"⚠️ Warning: {CSV_PATH} not found.")
    except Exception as e:
        print(f"❌ Error loading CSV: {e}")

load_csv_database()

# --- 2. FIREBASE CONNECTION ---
if not firebase_admin._apps:
    try:
        cred = credentials.Certificate("credentials.json")
        firebase_admin.initialize_app(cred)
        db = firestore.client()
    except Exception as e:
        print(f"🔥 Firebase error: {e}")
        db = None
else:
    db = firestore.client()

# --- 3. LOAD AI MODEL ---
def custom_preprocess(x): return x

try:
    with open("config.json", "r") as json_file:
        json_config = json_file.read()
    model = tf.keras.models.model_from_json(json_config, custom_objects={'preprocess_input': custom_preprocess})
    model.load_weights("model.weights.h5")
    
    # ⚠️ YOUR EXACT CLASS LIST
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
except Exception as e:
    print(f"❌ MODEL ERROR: {e}")
    model = None
    CLASS_NAMES = []

# --- 4. SEARCH HELPER ---
def search_database(predicted_label):
    clean_id = predicted_label.lower().strip()
    if '(' in clean_id: clean_id = clean_id.split('(')[0].strip()
    search_term = clean_id.replace("_", " ")

    # Check CSV
    if search_term in plant_database: return plant_database[search_term]
    
    # Check Firebase
    if db:
        doc = db.collection('plants').document(clean_id.replace(" ", "_")).get()
        if doc.exists:
            res = doc.to_dict()
            res['source'] = "Firebase"
            return res
            
    # Default Fallback
    return {
        "scientific_name": predicted_label,
        "common_name": predicted_label,
        "is_toxic": True,
        "symptoms": "Caution advised.",
        "poisoning_action": "Avoid ingestion.",
        "source": "AI Prediction"
    }

# --- 5. PREDICTION ENDPOINT ---
@app.route("/predict", methods=["POST"])
def predict():
    if not model: return jsonify({"error": "Model not loaded"}), 500
    if 'file' not in request.files: return jsonify({"error": "No file uploaded"}), 400
    
    try:
        file = request.files['file']
        image = Image.open(io.BytesIO(file.read())).convert('RGB')
        image = ImageOps.exif_transpose(image)
        image = image.resize((224, 224))
        
        # Simple Preprocess (Standard)
        img_array = np.array(image, dtype=np.float32)
        img_array = np.expand_dims(img_array, axis=0)
        
        # Predict
        preds = model.predict(img_array, verbose=0)
        idx = np.argmax(preds)
        confidence = float(np.max(preds))
        
        plant_name = CLASS_NAMES[idx] if idx < len(CLASS_NAMES) else "Unknown"
        
        # Get Info
        details = search_database(plant_name)
        details['confidence'] = confidence
        
        # ⚠️ CRITICAL: FREE MEMORY IMMEDIATELY
        del image, img_array, preds
        gc.collect() 
        
        return jsonify(details)

    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)