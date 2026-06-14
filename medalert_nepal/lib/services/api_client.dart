import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_config.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

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

          // Convert DioException to user-friendly ApiException
          final apiException = _convertDioException(e);
          return handler.reject(DioException(
            requestOptions: e.requestOptions,
            error: apiException,
            response: e.response,
            type: e.type,
          ));
        },
      ),
    );
  }

  ApiException _convertDioException(DioException e) {
    String message;
    int? statusCode = e.response?.statusCode;

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        message = 'Connection timeout. Please check your internet connection.';
        break;
      case DioExceptionType.badResponse:
        message = _handleErrorResponse(e.response?.statusCode, e.response?.data);
        break;
      case DioExceptionType.cancel:
        message = 'Request was cancelled.';
        break;
      case DioExceptionType.connectionError:
        message = 'No internet connection. Please check your network settings.';
        break;
      case DioExceptionType.badCertificate:
        message = 'SSL certificate error. Please try again later.';
        break;
      default:
        message = 'An unexpected error occurred. Please try again.';
    }

    return ApiException(message, statusCode);
  }

  String _handleErrorResponse(int? statusCode, dynamic responseData) {
    if (responseData is Map && responseData.containsKey('detail')) {
      return responseData['detail'] as String;
    }
    if (responseData is Map && responseData.containsKey('error')) {
      return responseData['error'] as String;
    }
    if (responseData is Map && responseData.containsKey('non_field_errors')) {
      final errors = responseData['non_field_errors'] as List;
      return errors.join(', ');
    }
    if (responseData is Map && responseData.containsKey('message')) {
      return responseData['message'] as String;
    }

    switch (statusCode) {
      case 400:
        return 'Invalid request. Please check your input.';
      case 401:
        return 'Authentication failed. Please login again.';
      case 403:
        return 'You don\'t have permission to access this resource.';
      case 404:
        return 'The requested resource was not found.';
      case 500:
        return 'Server error. Please try again later.';
      default:
        return 'Request failed with status $statusCode';
    }
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
