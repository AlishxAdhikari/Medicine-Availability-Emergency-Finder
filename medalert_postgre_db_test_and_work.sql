SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_name ILIKE '%pharm%';

  SELECT * FROM emergency_bloodstock;

  SELECT id, name FROM pharmacy_pharmacy;
  SELECT COUNT(*) FROM pharmacy_pharmacy;

INSERT INTO pharmacy_pharmacy 
(name, address, district, latitude, longitude, is_24_hour, is_verified, phone)
VALUES
('Jibika Pharmacy & Health Clinic', 'Sankhamul, Kathmandu', 'Kathmandu', 27.6852, 85.3331, false, true, '015521234'),
('Wasa Pasa Pharmacy', 'Gabahal, Lalitpur', 'Lalitpur', 27.6728, 85.3245, false, true, '015533747'),
('DajuBhai Pharmacy', 'Harisiddhi, Hattiban, Lalitpur', 'Lalitpur', 27.6485, 85.3372, false, true, '9848249044'),
('Happy Pills Pharmacy', 'Lagankhel, Lalitpur', 'Lalitpur', 27.6668, 85.3239, false, true, '9841567890'),
('Samidha Pharmacy', 'Lagankhel (opp. Academy of Culinary Arts), Lalitpur', 'Lalitpur', 27.6675, 85.3248, false, true, '9842415567'),
('Gushingal Medical Hall', 'Gushingal, Lalitpur', 'Lalitpur', 27.6750, 85.3200, false, true, '015543210'),
('Siddhi Medical Hall', 'Dhalayachha, Lalitpur', 'Lalitpur', 27.6705, 85.3180, false, true, '015512345'),
('Chyasal Medical Hall', 'Chyasal, Lalitpur', 'Lalitpur', 27.6785, 85.3255, false, true, '9841234567'),
('Sankhamul Pharma', 'Sankhamul Road, Lalitpur', 'Lalitpur', 27.6840, 85.3320, false, true, '9851098765'),
('Patan Dhoka Pharmacy', 'Patan Dhoka Road, Lalitpur', 'Lalitpur', 27.6730, 85.3250, false, true, '015567890');


SELECT id, name, phone, address 
FROM pharmacy_pharmacy 
ORDER BY id;


SELECT username FROM auth_user ORDER BY username;

SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'pharmacy_medicine'
ORDER BY ordinal_position;

SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'pharmacy_pharmacymedicinestock'
ORDER BY ordinal_position;

INSERT INTO pharmacy_medicine 
(name, generic_name, brand, category, dosage_form, strength, is_essential, requires_prescription)
VALUES
('Paracetamol 500mg', 'Paracetamol', 'Calpol', 'Analgesic', 'Tablet', '500mg', true, false),
('Amoxicillin 500mg', 'Amoxicillin', 'Mox', 'Antibiotic', 'Capsule', '500mg', true, true),
('Cetirizine 10mg', 'Cetirizine', 'Cetrizet', 'Antihistamine', 'Tablet', '10mg', true, false),
('Omeprazole 20mg', 'Omeprazole', 'Omez', 'Antacid', 'Capsule', '20mg', true, false),
('Metformin 500mg', 'Metformin', 'Glycomet', 'Antidiabetic', 'Tablet', '500mg', true, true),
('Amlodipine 5mg', 'Amlodipine', 'Amlong', 'Antihypertensive', 'Tablet', '5mg', true, true),
('Ibuprofen 400mg', 'Ibuprofen', 'Brufen', 'NSAID', 'Tablet', '400mg', true, false),
('ORS Powder', 'Oral Rehydration Salts', 'Electral', 'Electrolyte', 'Powder', '21.8g', true, false),
('Azithromycin 500mg', 'Azithromycin', 'Azithral', 'Antibiotic', 'Tablet', '500mg', true, true),
('Pantoprazole 40mg', 'Pantoprazole', 'Pan', 'Antacid', 'Tablet', '40mg', true, false);

INSERT INTO pharmacy_pharmacymedicinestock 
(quantity, price, low_threshold, medicine_id, pharmacy_id)
SELECT 
    (RANDOM() * 80 + 20)::INTEGER AS quantity,          -- quantity between 20-100
    ROUND((RANDOM() * 150 + 20)::NUMERIC, 2) AS price,  -- price between 20-170
    15 AS low_threshold,
    m.id AS medicine_id,
    p.id AS pharmacy_id
FROM pharmacy_medicine m
CROSS JOIN pharmacy_pharmacy p;

SELECT 
    p.name AS pharmacy,
    m.name AS medicine,
    s.quantity,
    s.price,
    s.low_threshold
FROM pharmacy_pharmacymedicinestock s
JOIN pharmacy_pharmacy p ON p.id = s.pharmacy_id
JOIN pharmacy_medicine m ON m.id = s.medicine_id
ORDER BY p.name, m.name
LIMIT 50;