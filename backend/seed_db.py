import firebase_admin
from firebase_admin import credentials, firestore
import pandas as pd

# Initialize Firebase
cred = credentials.Certificate("credentials.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

# Read CSV
df = pd.read_csv("toxic_plants_info.csv")

print("🚀 Starting Upload...")

for index, row in df.iterrows():
    # Create a consistent ID: "Aloe vera" -> "aloe_vera"
    clean_name = row['scientific_name'].strip().lower().replace(" ", "_")
    
    data = {
        "scientific_name": row['scientific_name'],
        "common_name": row['common_name'],
        "poisoning_action": row['poisoning_action'], # Maps to CSV column 
        "symptoms": row['symptoms'],                 # Maps to CSV column 
        "is_toxic": True,
        "source": "Curated Database"
    }
    
    # Upload to 'plants' collection
    db.collection('plants').document(clean_name).set(data)
    print(f"✅ Uploaded: {row['scientific_name']}")

print("🎉 Database Population Complete!")