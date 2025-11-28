import json
import requests
import time
from typing import Dict, Any
from concurrent.futures import ThreadPoolExecutor, as_completed
import threading

# Thread-safe counter
class Counter:
    def __init__(self):
        self.value = 0
        self.failed = 0
        self.lock = threading.Lock()
    
    def increment(self, failed=False):
        with self.lock:
            self.value += 1
            if failed:
                self.failed += 1

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
        
        address = data.get('address', {})
        road = address.get('road', '')
        
        if not road:
            road = address.get('pedestrian', '')
        if not road:
            road = address.get('suburb', '')
            
        return road
    except Exception as e:
        return ""

def process_stop(stop: Dict[str, Any], counter: Counter, total: int) -> Dict[str, Any]:
    """Process a single stop"""
    lat = float(stop['Latitude']) / 1000000
    lon = float(stop['Longitude']) / 1000000
    
    street_name = reverse_geocode(lat, lon)
    stop['Street Name'] = street_name
    
    counter.increment(failed=(not street_name))
    
    if counter.value % 100 == 0:
        print(f"Progress: {counter.value}/{total} ({counter.value / total * 100:.1f}%) - Failed: {counter.failed}")
    
    # Rate limiting
    time.sleep(1.1)
    
    return stop

def process_batch(input_file: str, output_file: str, start_idx: int = 0, batch_size: int = 1000):
    """
    Process stops in batches to allow resuming
    """
    print(f"Loading {input_file}...")
    
    with open(input_file, 'r', encoding='utf-8') as f:
        stops = json.load(f)
    
    total = len(stops)
    end_idx = min(start_idx + batch_size, total)
    
    print(f"Processing stops {start_idx} to {end_idx} of {total}...")
    
    counter = Counter()
    
    # Process the batch
    for i in range(start_idx, end_idx):
        stop = stops[i]
        
        # Skip if already has street name
        if 'Street Name' in stop and stop['Street Name']:
            counter.increment()
            continue
        
        lat = float(stop['Latitude']) / 1000000
        lon = float(stop['Longitude']) / 1000000
        
        street_name = reverse_geocode(lat, lon)
        stop['Street Name'] = street_name
        
        counter.increment(failed=(not street_name))
        
        if counter.value % 10 == 0:
            print(f"Progress: {counter.value}/{batch_size} - Failed: {counter.failed}")
        
        time.sleep(1.1)
    
    print(f"\nBatch complete! Processed: {counter.value}, Failed: {counter.failed}")
    
    # Save progress
    print(f"Saving to {output_file}...")
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(stops, f, ensure_ascii=False, indent=2)
    
    print("Saved!")
    return end_idx < total

if __name__ == "__main__":
    input_file = "paradas_de_onibus.json"
    output_file = "paradas_de_onibus_with_streets.json"
    
    print("=" * 60)
    print("Bus Stop Reverse Geocoding Script (BATCH MODE)")
    print("=" * 60)
    print()
    print("This script processes stops in batches of 1000.")
    print("You can stop and resume at any time.")
    print()
    
    start = int(input("Start index (0 for beginning): ") or "0")
    batch = int(input("Batch size (default 1000): ") or "1000")
    
    has_more = process_batch(input_file, output_file, start, batch)
    
    if has_more:
        print(f"\nTo continue, run: python reverse_geocode_stops_batch.py")
        print(f"And enter start index: {start + batch}")
