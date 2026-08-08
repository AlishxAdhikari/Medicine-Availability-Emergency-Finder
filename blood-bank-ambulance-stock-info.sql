INSERT INTO emergency_ambulanceprovider
(name, service_type, district, is_24_hour, has_icu, has_oxygen, phone)
VALUES
-- Kathmandu
('Nepal Ambulance Service (NAS) - 102', 'Advanced', 'Kathmandu', true, false, true, '102'),
('Nepal Red Cross Society Ambulance', 'Basic', 'Kathmandu', true, false, true, '01-4228094'),
('Grande International Hospital Ambulance', 'Advanced', 'Kathmandu', true, true, true, '01-5159266'),
('Norvic International Hospital Ambulance', 'Advanced', 'Kathmandu', true, true, true, '9803222222'),
('Paropakar Ambulance Service', 'Basic', 'Kathmandu', true, false, true, '01-4260859'),

-- Lalitpur
('Lalitpur Metropolitan Municipality Ambulance', 'Basic', 'Lalitpur', true, false, true, '01-5527003'),
('Lalitpur Red Cross Ambulance', 'Basic', 'Lalitpur', true, false, true, '01-5545666'),
('Patan Hospital Ambulance', 'Advanced', 'Lalitpur', true, true, true, '01-5522278'),
('B&B Hospital Ambulance', 'Advanced', 'Lalitpur', true, true, true, '01-5531933'),
('Alka Hospital Ambulance', 'Basic', 'Lalitpur', true, false, true, '01-5970795'),

-- Bhaktapur
('Bhaktapur Municipality Ambulance', 'Basic', 'Bhaktapur', true, false, true, '01-6613200'),
('Nepal Red Cross Society Bhaktapur', 'Basic', 'Bhaktapur', true, false, true, '01-6612266'),
('Dr. Iwamura Memorial Hospital Ambulance', 'Basic', 'Bhaktapur', true, false, true, '01-6612705'),
('Bhaktapur Cancer Hospital Ambulance', 'Advanced', 'Bhaktapur', true, true, true, '01-6611532'),
('Siddhi Memorial Hospital Ambulance', 'Basic', 'Bhaktapur', true, false, true, '01-6610570');


INSERT INTO emergency_bloodbank
(name, district, latitude, longitude, operating_hours, phone)
VALUES
-- ==================== KATHMANDU ====================
('Central NRCS Blood Bank (Bhrikuti Mandap)', 'Kathmandu', 27.7005, 85.3185, '24 Hours (Emergency)', '01-4288485'),
('Teaching Hospital (TUTH) Blood Bank', 'Kathmandu', 27.7362, 85.3306, '24 Hours', '01-4410911'),
('Bir Hospital Blood Bank', 'Kathmandu', 27.7055, 85.3140, '24 Hours', '01-4221119'),
('Gangalal National Heart Centre Blood Bank', 'Kathmandu', 27.7408, 85.3375, '24 Hours', '01-4371322'),
('Grande International Hospital Blood Bank', 'Kathmandu', 27.7485, 85.3250, '24 Hours', '01-5159266'),

-- ==================== LALITPUR ====================
('Lalitpur NRCS Blood Bank (Pulchowk)', 'Lalitpur', 27.6780, 85.3175, '24 Hours', '01-5427033'),
('Patan Hospital Blood Bank', 'Lalitpur', 27.6685, 85.3200, '24 Hours', '01-5522295'),
('Nepal Mediciti Hospital Blood Bank', 'Lalitpur', 27.6450, 85.3050, '24 Hours', '01-4217766'),
('Star Hospital Blood Bank', 'Lalitpur', 27.6800, 85.3100, '24 Hours', '01-5450198'),
('B&B Hospital Blood Bank', 'Lalitpur', 27.6650, 85.3250, '24 Hours', '01-5531933'),

-- ==================== BHAKTAPUR ====================
('Bhaktapur NRCS Blood Bank (Dudhpati)', 'Bhaktapur', 27.6720, 85.4295, '24 Hours', '01-6611661'),
('Bhaktapur Hospital Blood Bank', 'Bhaktapur', 27.6715, 85.4280, '24 Hours', '01-6610676'),
('Dr. Iwamura Memorial Hospital Blood Bank', 'Bhaktapur', 27.6750, 85.4200, '24 Hours', '01-6612705'),
('Siddhi Memorial Hospital Blood Bank', 'Bhaktapur', 27.6700, 85.4250, '24 Hours', '01-6610570'),
('Human Organ Transplant Centre Blood Bank', 'Bhaktapur', 27.6725, 85.4219, '24 Hours', '01-6614709');


INSERT INTO emergency_bloodstock
(blood_group, level, bank_id)
VALUES
-- ==================== Kathmandu Banks (id 1-5) ====================
-- 1. Central NRCS Blood Bank
('A+', 'High', 1),
('A-', 'Medium', 1),
('B+', 'High', 1),
('B-', 'Low', 1),
('AB+', 'Medium', 1),
('AB-', 'Critical', 1),
('O+', 'High', 1),
('O-', 'Low', 1),

-- 2. Teaching Hospital (TUTH)
('A+', 'Medium', 2),
('A-', 'Low', 2),
('B+', 'High', 2),
('B-', 'Medium', 2),
('AB+', 'Low', 2),
('AB-', 'Critical', 2),
('O+', 'High', 2),
('O-', 'Medium', 2),

-- 3. Bir Hospital
('A+', 'High', 3),
('A-', 'Medium', 3),
('B+', 'Medium', 3),
('B-', 'Low', 3),
('AB+', 'Medium', 3),
('AB-', 'Low', 3),
('O+', 'High', 3),
('O-', 'Critical', 3),

-- 4. Gangalal Heart Centre
('A+', 'Medium', 4),
('A-', 'Low', 4),
('B+', 'High', 4),
('B-', 'Medium', 4),
('AB+', 'Low', 4),
('AB-', 'Critical', 4),
('O+', 'High', 4),
('O-', 'Low', 4),

-- 5. Grande International Hospital
('A+', 'High', 5),
('A-', 'Medium', 5),
('B+', 'High', 5),
('B-', 'Low', 5),
('AB+', 'Medium', 5),
('AB-', 'Low', 5),
('O+', 'High', 5),
('O-', 'Medium', 5),

-- ==================== Lalitpur Banks (id 6-10) ====================
-- 6. Lalitpur NRCS Blood Bank
('A+', 'High', 6),
('A-', 'Low', 6),
('B+', 'High', 6),
('B-', 'Medium', 6),
('AB+', 'Low', 6),
('AB-', 'Critical', 6),
('O+', 'High', 6),
('O-', 'Low', 6),

-- 7. Patan Hospital
('A+', 'Medium', 7),
('A-', 'Medium', 7),
('B+', 'High', 7),
('B-', 'Low', 7),
('AB+', 'Medium', 7),
('AB-', 'Low', 7),
('O+', 'High', 7),
('O-', 'Critical', 7),

-- 8. Nepal Mediciti
('A+', 'High', 8),
('A-', 'Medium', 8),
('B+', 'High', 8),
('B-', 'Medium', 8),
('AB+', 'Low', 8),
('AB-', 'Low', 8),
('O+', 'High', 8),
('O-', 'Medium', 8),

-- 9. Star Hospital
('A+', 'Medium', 9),
('A-', 'Low', 9),
('B+', 'Medium', 9),
('B-', 'Low', 9),
('AB+', 'Medium', 9),
('AB-', 'Critical', 9),
('O+', 'High', 9),
('O-', 'Low', 9),

-- 10. B&B Hospital
('A+', 'High', 10),
('A-', 'Medium', 10),
('B+', 'High', 10),
('B-', 'Low', 10),
('AB+', 'Medium', 10),
('AB-', 'Low', 10),
('O+', 'High', 10),
('O-', 'Medium', 10),

-- ==================== Bhaktapur Banks (id 11-15) ====================
-- 11. Bhaktapur NRCS Blood Bank
('A+', 'High', 11),
('A-', 'Low', 11),
('B+', 'High', 11),
('B-', 'Medium', 11),
('AB+', 'Low', 11),
('AB-', 'Critical', 11),
('O+', 'High', 11),
('O-', 'Low', 11),

-- 12. Bhaktapur Hospital
('A+', 'Medium', 12),
('A-', 'Medium', 12),
('B+', 'High', 12),
('B-', 'Low', 12),
('AB+', 'Medium', 12),
('AB-', 'Low', 12),
('O+', 'High', 12),
('O-', 'Critical', 12),

-- 13. Dr. Iwamura Memorial Hospital
('A+', 'High', 13),
('A-', 'Low', 13),
('B+', 'Medium', 13),
('B-', 'Medium', 13),
('AB+', 'Low', 13),
('AB-', 'Critical', 13),
('O+', 'High', 13),
('O-', 'Low', 13),

-- 14. Siddhi Memorial Hospital
('A+', 'Medium', 14),
('A-', 'Medium', 14),
('B+', 'High', 14),
('B-', 'Low', 14),
('AB+', 'Medium', 14),
('AB-', 'Low', 14),
('O+', 'High', 14),
('O-', 'Medium', 14),

-- 15. Human Organ Transplant Centre
('A+', 'High', 15),
('A-', 'Low', 15),
('B+', 'High', 15),
('B-', 'Medium', 15),
('AB+', 'Low', 15),
('AB-', 'Critical', 15),
('O+', 'High', 15),
('O-', 'Low', 15);