import requests
import os

# 1. SETUP
# 👇 This is your NEW valid key
API_KEY = "2b1086jYm9N1RYVXfgi6wcKPO"  
PROJECT = "all" 
api_endpoint = f"https://my-api.plantnet.org/v2/identify/{PROJECT}?api-key={API_KEY}"

# 2. IMAGE PATH 
# ⚠️ IMPORTANT: You must have a file named 'test_flower.jpg' in the same folder as this script!
image_path = "test_flower.jpg" 

def test_api():
    print(f"--- Starting Pl@ntNet API Test ---")
    print(f"🔑 Using Key: {API_KEY}")
    
    # Debug: Print where python is looking for the file
    current_dir = os.path.dirname(os.path.abspath(__file__))
    full_path = os.path.join(current_dir, image_path)
    print(f"🔍 Looking for image at: {full_path}")

    try:
        with open(full_path, "rb") as file:
            files = {'images': (image_path, file)}
            data = {'organs': ['flower']}
            
            print("🚀 Sending request to Pl@ntNet...")
            req = requests.post(api_endpoint, files=files, data=data)
            
            print(f"📡 Status Code: {req.status_code}")
            
            if req.status_code == 200:
                json_result = req.json()
                print("✅ SUCCESS! API is working.")
                
                # specific check to ensure 'results' isn't empty
                if 'results' in json_result and len(json_result['results']) > 0:
                    best_match = json_result['results'][0]
                    plant_name = best_match['species']['scientificNameWithoutAuthor']
                    common_name = best_match['species']['commonNames'][0] if best_match['species']['commonNames'] else "No common name"
                    score = best_match['score']
                    
                    print(f"🌿 Detected: {plant_name} ({common_name})")
                    print(f"📊 Confidence: {score * 100:.2f}%")
                else:
                    print("⚠️ API worked, but found no matching plants.")
            else:
                print("❌ ERROR RESPONSE from Server:")
                print(req.text)
                
    except FileNotFoundError:
        print(f"\n❌ CRITICAL ERROR: Could not find '{image_path}'")
        print(f"👉 Please copy a flower image into this folder: {current_dir}")
        print(f"👉 Rename it to '{image_path}' and try again.")
    except Exception as e:
        print(f"❌ Exception: {e}")

if __name__ == "__main__":
    test_api()