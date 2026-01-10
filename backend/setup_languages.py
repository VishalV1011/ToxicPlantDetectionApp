import os
import json
import time
from deep_translator import GoogleTranslator

# --- 1. CONFIGURATION ---
# The master English data.
ENGLISH_DATA = {
    # --- MAIN UI ---
    "app_title": "FloraGuard",
    "scan_plant": "Scan a Plant",
    "camera": "Camera",
    "gallery": "Gallery",
    "settings": "Language Settings",
    "download": "Download",
    "installed": "Installed",
    "active": "Active",
    "switch": "Switch",
    "loading": "Analyzing...",

    # --- TOXIC SCREEN LABELS ---
    "toxic": "TOXIC PLANT",
    "confidence": "Confidence",
    "symptoms": "SYMPTOMS",
    "action": "FIRST AID",

    # --- SAFE SCREEN LABELS ---
    "safe": "LIKELY SAFE",
    "safe_title": "No Toxic Plant Detected",
    "safe_analysis": "ANALYSIS",      # Alternative header for "Symptoms"
    "safe_advice": "RECOMMENDATION",  # Alternative header for "First Aid"
    
    # Static content for Safe Screen
    "safe_body_text": "The image does not match any known toxic plants in our database with high confidence.",
    "safe_action_text": "Likely safe. However, never ingest unknown plants.",

    # 👇 NEW KEYS ADDED HERE 👇
    "source_label": "Source",
    "safe_body_plantnet": "Identified as likely safe or non-toxic by visual analysis."
}

# List of languages to generate.
# Keys are ISO codes (must match Google Translate support).
LANGUAGES = {
    "en": "English",
    "zh-CN": "中文",
    "es": "Español",
    "hi": "हिन्दी",
    "ar": "العربية",
    "pt": "Português",
    "bn": "বাংলা",
    "ru": "Русский",
    "fr": "Français",
    "id": "Bahasa Indonesia",
    "ms": "Bahasa Melayu"
}

OUTPUT_FOLDER = 'languages'

# --- 2. TRANSLATION LOGIC ---
def get_translated_dict(data, target_lang):
    """
    Translates dictionary values from English to target_lang.
    """
    new_data = {}
    translator = GoogleTranslator(source='en', target=target_lang)
    
    print(f"   Translating {len(data)} labels...", end='\r')
    
    for key, text in data.items():
        try:
            # Skip translation for app title if you want it to stay "FloraGuard" everywhere
            if key == "app_title":
                new_data[key] = text
                continue

            translated_text = translator.translate(text)
            new_data[key] = translated_text
            
            # Small sleep to be polite to the API
            time.sleep(0.1) 
            
        except Exception as e:
            print(f"   [!] Error translating '{key}': {e}")
            new_data[key] = text # Fallback to English
            
    return new_data

def main():
    # Create folder if not exists
    if not os.path.exists(OUTPUT_FOLDER):
        os.makedirs(OUTPUT_FOLDER)
        print(f"Created folder: {OUTPUT_FOLDER}/")

    print(f"--- Starting UI Translation for {len(LANGUAGES)} languages ---")

    for code, native_name in LANGUAGES.items():
        print(f"Processing: {native_name} ({code})...")
        
        # Prepare the file structure
        # This structure is vital for the App to read the Native Name
        final_structure = {
            "nativeName": native_name,
            "name": code,
            "data": {}
        }

        # Generate Data
        if code == 'en':
            final_structure["data"] = ENGLISH_DATA
        else:
            final_structure["data"] = get_translated_dict(ENGLISH_DATA, code)

        # Write to JSON
        file_path = f"{OUTPUT_FOLDER}/{code}.json"
        with open(file_path, 'w', encoding='utf-8') as f:
            # FIX IS HERE: We dump 'final_structure', NOT 'final_structure["data"]'
            json.dump(final_structure, f, ensure_ascii=False, indent=2)
            
        print(f"   ✅ Saved to {file_path}")

    print("\n🎉 All language files generated successfully!")

if __name__ == "__main__":
    main()