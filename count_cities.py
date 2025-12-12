import csv

filename = '/home/sergio/phd/des_julia_6g_rupa/data/usa/agent-unprocessed-raw-datasets/uscities.csv'

count_50k = 0
count_50k_incorporated = 0
count_50k_incorporated_conus = 0

with open(filename, 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for row in reader:
        try:
            pop = float(row['population'])
            if pop >= 50000:
                count_50k += 1
                if row['incorporated'] == 'TRUE':
                    count_50k_incorporated += 1
                    
                    lat = float(row['lat'])
                    lng = float(row['lng'])
                    if 24.0 < lat < 50.0 and -125.0 < lng < -66.0:
                        count_50k_incorporated_conus += 1
        except ValueError:
            continue

print(f"Total cities with population >= 50,000: {count_50k}")
print(f"Incorporated cities with population >= 50,000: {count_50k_incorporated}")
print(f"Incorporated cities (CONUS) with population >= 50,000: {count_50k_incorporated_conus}")
