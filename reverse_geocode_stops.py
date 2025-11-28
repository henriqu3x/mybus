import json
import requests
import time
from typing import Dict, Any

def reverse_geocode(lat: float, lon: float) -> str:
    """
    Perform reverse geocoding using Nominatim API
    Returns the street name (road) or empty string if not found
    """
    url = f"https://nominatim.openstreetmap.org/reverse?lat={lat}&lon={lon}&format=json"
    
    headers = {
        'User-Agent': 'MyBusApp/1.0 (bus stop mapping)'
    }
    
    try:
        response = requests.get(url, headers=headers, timeout=10)
        response.raise_for_status()
        data = response.json()
        
        # Try to get the road name from the address
        address = data.get('address', {})
        road = address.get('road', '')
        
        # If no road, try other fields
        if not road:
            road = address.get('pedestrian', '')
        if not road:
            road = address.get('suburb', '')
            
        return road
    except Exception as e:
        print(f"Error geocoding ({lat}, {lon}): {e}")
        return ""

def process_stops_file(input_file: str, output_file: str):
    """
    Process the bus stops JSON file and add street names
    """
    print(f"Loading {input_file}...")
    
    with open(input_file, 'r', encoding='utf-8') as f:
        stops = json.load(f)
    
    total = len(stops)
    print(f"Processing {total} stops...")
    
    processed = 0
    failed = 0
    
    for i, stop in enumerate(stops):
        # Convert coordinates
        lat = float(stop['Latitude']) / 1000000
        lon = float(stop['Longitude']) / 1000000
        
        # Get street name
        street_name = reverse_geocode(lat, lon)
        
        # Add to the stop data
        stop['Street Name'] = street_name
        
        processed += 1
        
        if not street_name:
            failed += 1
        
        # Progress update
        if (i + 1) % 10 == 0:
            print(f"Progress: {i + 1}/{total} ({(i + 1) / total * 100:.1f}%) - Failed: {failed}")
        
        # Rate limiting - Nominatim allows 1 request per second
        time.sleep(1.1)
    
    print(f"\nProcessing complete!")
    print(f"Total: {total}")
    print(f"Processed: {processed}")
    print(f"Failed: {failed}")
    
    # Save the updated data
    print(f"\nSaving to {output_file}...")
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(stops, f, ensure_ascii=False, indent=2)
    
    print("Done!")

if __name__ == "__main__":
    input_file = "paradas_de_onibus.json"
    output_file = "paradas_de_onibus_with_streets.json"
    
    print("=" * 60)
    print("Bus Stop Reverse Geocoding Script")
    print("=" * 60)
    print()
    print("WARNING: This will take a LONG time!")
    print(f"Estimated time: ~40 hours for 143k stops (1 req/sec)")
    print()
    
    response = input("Do you want to continue? (yes/no): ")
    
    if response.lower() == 'yes':
        process_stops_file(input_file, output_file)
    else:
        print("Cancelled.")
