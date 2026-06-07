class ApiConfig {
  static const String baseUrl = 'http://10.0.2.2:8000/api/v1'; // Android emulator
  static const String localBaseUrl = 'http://127.0.0.1:8000/api/v1'; // iOS / Web / Desktop
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);
}
