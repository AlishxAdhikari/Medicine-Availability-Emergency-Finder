class BloodBank {
  final String bankName;
  final String location;
  final Map<String, String> bloodStockStatus; // e.g., {'A+': 'Available', 'O-': 'Critical Stock'}
  final double distance;

  BloodBank({
    required this.bankName,
    required this.location,
    required this.bloodStockStatus,
    required this.distance,
  });
}