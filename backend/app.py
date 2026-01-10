import os
import json
import io
import platform
import subprocess
import numpy as np
import tensorflow as tf
from PIL import Image, ImageOps
from flask import Flask, jsonify, request, send_from_directory
import requests
import firebase_admin
from firebase_admin import credentials, firestore
from deep_translator import GoogleTranslator
import concurrent.futures

app = Flask(__name__)

# --- 1. CONFIGURATION ---
PERENUAL_API_KEY = "sk-tiQN690a1efb6d2a713302"

# 🌿 PLANTNET CONFIGURATION
PLANTNET_API_KEY = "2b1086jYm9N1RYVXfgi6wcKPO"
PLANTNET_URL = "https://my-api.plantnet.org/v2/identify/all"

# 🔔 AUDIO SETTINGS
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
AUDIO_TOXIC = os.path.join(BASE_DIR, "toxic.wav")
AUDIO_SAFE = os.path.join(BASE_DIR, "non_toxic.wav")

# ⏱️ TIMEOUT SETTING
TRANSLATION_TIMEOUT = 10.0 
TRANSLATION_CACHE = {}

# 🛡️ SAFETY SETTINGS
CONFIDENCE_THRESHOLD = 0.70 
SAFE_CLASSES = ['heliconia rostrata', 'ayushvision_flowers', 'wild gooseberry']

# 🖼️ FILE VALIDATION SETTINGS
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg'}

# 🚀 GLOBAL EXECUTOR
executor = concurrent.futures.ThreadPoolExecutor(max_workers=3)

# --- HELPER: CHECK FILE EXTENSION ---
def allowed_file(filename):
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

# --- AUDIO PLAYER (Server Side) ---
def play_audio_server_side(filepath):
    print(f"🔍 Looking for audio at: {filepath}")
    if not os.path.exists(filepath):
        print(f"❌ ERROR: Audio file NOT found at: {filepath}")
        return
    try:
        system_os = platform.system()
        if system_os == "Windows":
            import winsound
            winsound.PlaySound(filepath, winsound.SND_FILENAME | winsound.SND_ASYNC | winsound.SND_NODEFAULT)
        elif system_os == "Darwin":
            subprocess.run(["afplay", filepath], check=False)
        else:
            subprocess.run(["aplay", filepath], check=False)
    except Exception as e:
        print(f"❌ Audio Error: {e}")

# --- 2. TRANSLATION HELPER ---
def fetch_translation_api(text, target_lang):
    try:
        return GoogleTranslator(source='auto', target=target_lang).translate(text)
    except Exception as e:
        print(f"   [!] Google API Failed: {e}")
        return None

def smart_translate(text, target_lang):
    if not text or str(text).strip() == "" or text == "Unknown": return text
    if target_lang == 'en': return text
    cache_key = f"{target_lang}_{text}"
    if cache_key in TRANSLATION_CACHE: return TRANSLATION_CACHE[cache_key]
    future = executor.submit(fetch_translation_api, text, target_lang)
    try:
        result = future.result(timeout=TRANSLATION_TIMEOUT)
        if result:
            TRANSLATION_CACHE[cache_key] = result
            return result
        else:
            return text
    except Exception:
        return text

# --- LOCAL LANGUAGE LOADER ---
def get_local_text(lang_code, key, default_text):
    if lang_code == 'en': return default_text
    try:
        file_path = f"languages/{lang_code}.json"
        if os.path.exists(file_path):
            with open(file_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
                if "data" in data and key in data["data"]:
                    return data["data"][key]
    except Exception as e:
        print(f"   [!] Failed to load local language file: {e}")
    return smart_translate(default_text, lang_code)

# --- 3. PLANTNET HELPER ---
def identify_with_plantnet(image_bytes):
    print("🌿 Sending image to Pl@ntNet API...")
    try:
        files = {'images': ('image.jpg', io.BytesIO(image_bytes))}
        params = {
            'api-key': PLANTNET_API_KEY,
            'include-related-images': 'false',
            'lang': 'en'
        }
        response = requests.post(PLANTNET_URL, files=files, params=params)
        
        if response.status_code == 200:
            data = response.json()
            if 'results' in data and len(data['results']) > 0:
                best_match = data['results'][0]
                species = best_match['species']
                scientific_name = species.get('scientificNameWithoutAuthor', 'Unknown Plant')
                common_names = species.get('commonNames', [])
                common_name = common_names[0] if common_names else scientific_name
                score = best_match.get('score', 0)
                
                print(f"✅ Pl@ntNet Match: {common_name} ({score:.2f})")
                
                return {
                    "scientific_name": scientific_name,
                    "common_name": common_name,
                    "confidence": score
                }
        else:
            print(f"❌ API Error Response: {response.text}")
    except Exception as e:
        print(f"⚠️ Pl@ntNet Exception: {e}")
    return None

# --- 4. LOAD FIREBASE ONLY ---
print("⏳ Connecting to Firebase...")
if not firebase_admin._apps:
    try:
        cred = credentials.Certificate("credentials.json")
        firebase_admin.initialize_app(cred)
        db = firestore.client()
        print("✅ Firebase Connected")
    except Exception as e: 
        print(f"❌ Firebase Error: {e}")
        db = None
else: 
    db = firestore.client()
    print("✅ Firebase Connected")

def custom_preprocess(x): return x
try:
    with open("config.json", "r") as f: json_config = f.read()
    model = tf.keras.models.model_from_json(json_config, custom_objects={'preprocess_input': custom_preprocess})
    model.load_weights("model.weights.h5")
    CLASS_NAMES = [
        'Abrus precatorius', 'Acalypha indica', 'Anacardium occidentale', 'Annona_muricata', 
        'Annona_squamosa', 'Aristolochia tagala', 'Asthma-plant (Euphorbia hirta)', 
        'Ayushvision_flowers', 'Blind-your-eye Mangrove (Excoecaria agallocha)', 'Cerbera_odollam', 
        'Clerodendrum inerme', 'Croton tiglium', 'Devil backbone(euphorbia tithymaloides)', 
        'Dioscorea hispida Dennst', 'Euphorbia Milli', 'Heart of Jesus (caladium bicolor)', 
        'Kigelia_africana', 'Oleander', 'Pencil tree (euphorbia tirucalli)', 'Phytolacca_octandra', 
        'Poisonous American Mushrooms', 'Senna Alata', 'Solanum nigrum', 'Sterculia_foetida', 
        'Strychnos_nux-vomica', 'adenium obesum', 'aloe vera', 'heliconia rostrata', 
        'poisen ivy', 'wild gooseberry'
    ]
except: model = None; CLASS_NAMES = []

# --- 5. SEARCH LOGIC (FIXED FOR FIREBASE KEYS) ---
def search_database(predicted_label, lang_code='en'):
    # 1. Clean the ID logic
    clean_id = predicted_label.lower().strip()
    
    # Handle parens (e.g., "Pencil tree (euphorbia tirucalli)" -> "euphorbia tirucalli")
    if '(' in clean_id: 
        clean_id = clean_id[clean_id.find('(')+1:clean_id.find(')')].strip()
    
    # 🛑 CRITICAL FIX: Replace spaces with underscores to match Firebase IDs
    # "euphorbia tirucalli" -> "euphorbia_tirucalli"
    clean_id = clean_id.replace(' ', '_')
    
    # 2. CHECK FIREBASE
    if db is not None:
        try:
            print(f"🔎 Checking Firebase for ID: '{clean_id}'") # Debug print
            doc_ref = db.collection('plants').document(clean_id)
            doc = doc_ref.get()
            
            if doc.exists:
                print(f"🔥 Found in Firebase: {clean_id}")
                data = doc.to_dict()
                
                # Helper to get value with on-the-fly translation
                def get_val(key):
                    target_key = f"{key}_{lang_code}"
                    if lang_code != 'en' and target_key in data and data[target_key]:
                        return data[target_key]
                    text = data.get(key, "Unknown")
                    return smart_translate(text, lang_code)

                return {
                    "scientific_name": data.get('scientific_name', predicted_label),
                    "common_name": get_val('common_name'),
                    "symptoms": get_val('symptoms'),
                    "poisoning_action": get_val('poisoning_action'),
                    "is_toxic": True, # Force Toxic if found
                    "source": "Firebase Database",
                    "reference_image": data.get('image_folder', None)
                }
            else:
                print(f"⚠️ Not found in Firebase: '{clean_id}'") # Debug print
        except Exception as e:
            print(f"❌ Firebase Check Failed: {e}")

    # 3. NOT FOUND -> RETURN SAFE/UNKNOWN
    base_symptoms = "Caution advised. Exact symptoms unknown."
    base_action = "Avoid ingestion. Seek medical help."
    
    return {
        "scientific_name": predicted_label,
        "common_name": predicted_label,
        "symptoms": smart_translate(base_symptoms, lang_code),
        "poisoning_action": smart_translate(base_action, lang_code),
        "is_toxic": False,
        "source": "AI Prediction"
    }

# --- 6. ROUTES ---
@app.route('/languages', methods=['GET'])
def list_languages():
    return jsonify([
        {"code": "en", "name": "English", "nativeName": "English"},
        {"code": "zh-CN", "name": "Chinese", "nativeName": "中文"},
        {"code": "hi", "name": "Hindi", "nativeName": "हिन्दी"},
        {"code": "es", "name": "Spanish", "nativeName": "Español"},
        {"code": "fr", "name": "French", "nativeName": "Français"},
        {"code": "ar", "name": "Arabic", "nativeName": "العربية"},
        {"code": "bn", "name": "Bengali", "nativeName": "বাংলা"},
        {"code": "ru", "name": "Russian", "nativeName": "Русский"},
        {"code": "pt", "name": "Portuguese", "nativeName": "Português"},
        {"code": "id", "name": "Indonesian", "nativeName": "Bahasa Indonesia"},
        {"code": "ms", "name": "Malay", "nativeName": "Bahasa Melayu"}
    ])

@app.route('/languages/<lang_code>', methods=['GET'])
def get_language_file(lang_code):
    try: return send_from_directory('languages', f'{lang_code}.json')
    except: return jsonify({"error": "File not found"}), 404

# --- TEST EXTRACT ROUTE ---
@app.route('/test-extract/<plant_name>', methods=['GET'])
def test_extract(plant_name):
    if not db:
        return jsonify({"error": "Firebase not connected"}), 500
    try:
        # Match the logic in search_database
        clean_id = plant_name.lower().strip().replace(' ', '_')
        if '(' in clean_id: 
             clean_id = clean_id[clean_id.find('(')+1:clean_id.find(')')].strip().replace(' ', '_')

        print(f"🔎 Testing extraction for ID: {clean_id}")
        doc_ref = db.collection('plants').document(clean_id)
        doc = doc_ref.get()

        if doc.exists:
            data = doc.to_dict()
            return jsonify({
                "status": "success",
                "message": f"Data found for {clean_id}",
                "extracted_data": data
            }), 200
        else:
            return jsonify({
                "status": "not_found",
                "message": f"No document found in 'plants' collection with ID: {clean_id}"
            }), 404
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# --- 7. PREDICTION ENDPOINT ---
@app.route("/predict", methods=["POST"])
def predict():
    if not model: return jsonify({"error": "Model failed"}), 500
    if 'file' not in request.files: return jsonify({"error": "No file"}), 400
    
    user_lang = request.args.get('lang') or request.form.get('lang') or 'en'
    if user_lang == 'zh': user_lang = 'zh-CN'

    try:
        file = request.files['file']
        if file.filename == '' or not allowed_file(file.filename):
            print(f"🚫 Rejected file: {file.filename}")
            return jsonify({
                "error": "Invalid file type. Please upload a JPEG or PNG image.",
                "is_toxic": False 
            }), 400

        file_bytes = file.read()
        img = Image.open(io.BytesIO(file_bytes)).convert('RGB')
        img = ImageOps.exif_transpose(img)
        img = img.resize((224, 224), Image.Resampling.LANCZOS)
        img_array = np.array(img, dtype=np.float32)

        input_norm = np.expand_dims(img_array / 255.0, axis=0)
        preds = model.predict(input_norm, verbose=0)
        best_conf = float(np.max(preds))
        best_idx = np.argmax(preds)

        # 1. GET TENSORFLOW PREDICTION
        plant_name = CLASS_NAMES[best_idx] if best_idx < len(CLASS_NAMES) else "Unknown"
        
        # 2. CHECK DATABASE (Firebase)
        details = search_database(plant_name, lang_code=user_lang)
        
        # 3. DETERMINE IF WE NEED PLANTNET
        needs_plantnet = (best_conf < CONFIDENCE_THRESHOLD) or (details['source'] == "AI Prediction")

        if needs_plantnet:
            print(f"🛡️ Triggering Pl@ntNet (Conf: {best_conf:.2f} | Source: {details['source']})")
            
            plantnet_result = identify_with_plantnet(file_bytes)
            
            # Prepare Defaults (Safe)
            final_name = "Unknown / Safe"
            final_common = get_local_text(user_lang, "safe_title", "No Toxic Plant Detected")
            final_symptoms = get_local_text(user_lang, "safe_body_text", "The image does not match any known toxic plants.")
            final_action = get_local_text(user_lang, "safe_action_text", "Likely safe. However, never ingest unknown plants.")
            is_toxic_result = False
            source_tag = "Safety Threshold"

            if plantnet_result:
                p_scientific = plantnet_result['scientific_name']
                print(f"🧐 Pl@ntNet Identified: {p_scientific}. Checking database...")
                
                # Check Database with Pl@ntNet Name
                db_check = search_database(p_scientific, lang_code=user_lang)
                
                # If found in Firebase (source != AI Prediction), FORCE TOXIC
                if db_check['source'] != "AI Prediction":
                    print(f"✅ Found in Firebase ({db_check['source']}). Classifying as TOXIC.")
                    is_toxic_result = True 
                    final_name = db_check['scientific_name']
                    final_common = db_check['common_name']
                    final_symptoms = db_check['symptoms']
                    final_action = db_check['poisoning_action']
                    source_tag = f"Pl@ntNet + {db_check['source']}"
                else:
                    # Not in DB -> Assume Safe
                    print("✅ Plant not found in toxic DB. Assuming Safe.")
                    final_name = p_scientific
                    final_common = smart_translate(plantnet_result['common_name'], user_lang)
                    final_symptoms = get_local_text(user_lang, "safe_body_plantnet", "Identified as likely safe or non-toxic by visual analysis.")
                    source_tag = "Pl@ntNet API"

            if is_toxic_result:
                play_audio_server_side(AUDIO_TOXIC)
            else:
                play_audio_server_side(AUDIO_SAFE)

            return jsonify({
                "scientific_name": final_name,
                "common_name": final_common,
                "symptoms": final_symptoms,
                "poisoning_action": final_action,
                "is_toxic": is_toxic_result,
                "confidence": plantnet_result['confidence'] if plantnet_result else best_conf,
                "source": source_tag
            })

        # --- HIGH CONFIDENCE & FOUND IN DB ---
        if details.get('is_toxic', False):
            play_audio_server_side(AUDIO_TOXIC)
        else:
            play_audio_server_side(AUDIO_SAFE)
        
        details['confidence'] = best_conf
        print(f"🏆 Local Match: {plant_name} ({best_conf:.2f}) -> Toxic: {details['is_toxic']}")
        return jsonify(details)

    except Exception as e:
        print(f"Error: {e}")
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True, threaded=True)