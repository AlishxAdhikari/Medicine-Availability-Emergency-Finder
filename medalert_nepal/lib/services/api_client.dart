import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_config.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio dio;
  final _storage = const FlutterSecureStorage();

  ApiClient._internal() {
    dio = Dio(
      BaseOptions(
        baseUrl: _determineBaseUrl(),
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Logging & JWT Auth Interceptor
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Retrieve access token
          final token = await _storage.read(key: 'access_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          if (kDebugMode) {
            print('API REQUEST[${options.method}] => PATH: ${options.path}');
          }
          return handler.next(options);
        },
        onResponse: (response, handler) {
          if (kDebugMode) {
            print('API RESPONSE[${response.statusCode}] => PATH: ${response.requestOptions.path}');
          }
          return handler.next(response);
        },
        onError: (DioException e, handler) async {
          if (kDebugMode) {
            print('API ERROR[${e.response?.statusCode}] => PATH: ${e.requestOptions.path}');
            print('ERROR MESSAGE: ${e.message}');
          }

          // Handle Token Refresh on 401 Unauthorized
          if (e.response?.statusCode == 401 && e.requestOptions.path != '/auth/token/') {
            final refreshed = await _attemptTokenRefresh();
            if (refreshed) {
              // Retry original request with new token
              final token = await _storage.read(key: 'access_token');
              final options = e.requestOptions;
              options.headers['Authorization'] = 'Bearer $token';
              try {
                final cloneReq = await dio.fetch(options);
                return handler.resolve(cloneReq);
              } catch (retryError) {
                return handler.next(e);
              }
            }
          }
          return handler.next(e);
        },
      ),
    );
  }

  String _determineBaseUrl() {
    if (kIsWeb) {
      return ApiConfig.localBaseUrl;
    }
    try {
      if (Platform.isAndroid) {
        return ApiConfig.baseUrl;
      }
    } catch (_) {}
    return ApiConfig.localBaseUrl;
  }

  Future<bool> _attemptTokenRefresh() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken == null) return false;

    try {
      final response = await dio.post('/auth/token/refresh/', data: {
        'refresh': refreshToken,
      });
      if (response.statusCode == 200) {
        final newAccess = response.data['access'] as String;
        await _storage.write(key: 'access_token', value: newAccess);
        if (response.data['refresh'] != null) {
          await _storage.write(key: 'refresh_token', value: response.data['refresh'] as String);
        }
        return true;
      }
    } catch (_) {
      // Clear tokens if refresh fails (session expired)
      await _storage.delete(key: 'access_token');
      await _storage.delete(key: 'refresh_token');
    }
    return false;
  }
}
