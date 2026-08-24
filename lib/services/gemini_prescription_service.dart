import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class GeminiPrescriptionService {
  GeminiPrescriptionService._internal();
  static final GeminiPrescriptionService instance =
      GeminiPrescriptionService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const String _apiKeyStorageKey = 'gemini_api_key';

  static const String _apiBase =
      'https://generativelanguage.googleapis.com/v1beta';

  /// Models to try, best first.
  ///
  /// This used to be a single hardcoded `gemini-1.5-flash`, which Google
  /// retired from v1beta -- the app then failed with "is not found for API
  /// version v1beta", which reads like a broken API key rather than a model
  /// that no longer exists. Google retires these on its own schedule, so the
  /// name is no longer a constant the app depends on: if none of these
  /// resolve, [_discoverModel] asks the API what it actually has.
  ///
  /// Flash variants only: this is one image and a short reply on a free-tier
  /// key, and the Pro models are slower and more heavily rate-limited for no
  /// benefit at this task.
  static const List<String> _preferredModels = [
    'gemini-2.5-flash',
    'gemini-2.0-flash',
    'gemini-flash-latest',
  ];

  /// Cached for the process once something works, so a scan costs one request
  /// rather than re-walking the preference list every time.
  static String? _resolvedModel;

  /// Injectable so tests can drive the fallback without a network or a key.
  http.Client _client = http.Client();

  // ignore: avoid_setters_without_getters
  set clientForTest(http.Client client) => _client = client;

  static void resetResolvedModelForTest() => _resolvedModel = null;

  /// Retrieves the saved Gemini API key from secure storage.
  Future<String?> getApiKey() async {
    return await _storage.read(key: _apiKeyStorageKey);
  }

  /// Saves a user-provided Gemini API key to secure storage.
  Future<void> setApiKey(String key) async {
    await _storage.write(key: _apiKeyStorageKey, value: key.trim());
  }

  /// Sends a prescription photo to the Google Gemini API to extract medicine
  /// names. Returns a list of extracted medicine names.
  Future<List<String>> analyzePrescriptionImage(
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
    String? overrideApiKey,
  }) async {
    final apiKey = overrideApiKey ?? await getApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw Exception(
        'Gemini API key is required. Please set your API key first.',
      );
    }

    final requestBody = _buildRequestBody(imageBytes, mimeType);

    // Try the cached model first, then each preferred one. A model that has
    // been retired answers 404, which is worth walking past rather than
    // surfacing -- the next name in the list usually works.
    final candidates = <String>[
      ?_resolvedModel,
      ..._preferredModels.where((m) => m != _resolvedModel),
    ];

    http.Response? lastNotFound;
    for (final model in candidates) {
      final response = await _generate(model, apiKey, requestBody);
      if (response.statusCode == 200) {
        _resolvedModel = model;
        return _parseMedicines(response.body);
      }
      if (response.statusCode == 404) {
        lastNotFound = response;
        continue;
      }
      // Anything else (401 bad key, 429 rate limit, 500) is about this
      // request, not the model name, so stop and report it as-is.
      throw Exception(_errorMessage(response));
    }

    // Every name we know about is gone. Do what the API's own error message
    // tells you to do: ask it what it has.
    final discovered = await _discoverModel(apiKey);
    if (discovered != null) {
      final response = await _generate(discovered, apiKey, requestBody);
      if (response.statusCode == 200) {
        _resolvedModel = discovered;
        return _parseMedicines(response.body);
      }
      throw Exception(_errorMessage(response));
    }

    throw Exception(
      'No Gemini model on this API key supports image analysis. '
      '${lastNotFound == null ? '' : _errorMessage(lastNotFound)}',
    );
  }

  String _buildRequestBody(Uint8List imageBytes, String mimeType) {
    return jsonEncode({
      'contents': [
        {
          'parts': [
            {
              'text':
                  'You are a medical OCR scanner. Analyze this prescription '
                  'photo and extract only the names of the prescribed '
                  'medicines/medications. Return ONLY a comma-separated list '
                  'of the medicine names (e.g. Amoxicillin, Paracetamol, '
                  'Metformin). Do not include any explanations, bullet '
                  'points, numbering, or preamble.',
            },
            {
              'inline_data': {
                'mime_type': mimeType,
                'data': base64Encode(imageBytes),
              },
            },
          ],
        },
      ],
    });
  }

  Future<http.Response> _generate(
    String model,
    String apiKey,
    String body,
  ) async {
    return _client.post(
      Uri.parse('$_apiBase/models/$model:generateContent?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
  }

  /// Asks the API which models this key can actually use, and picks the
  /// cheapest one that can accept an image.
  ///
  /// Returns null when the call fails or nothing suitable comes back, so the
  /// caller can report the original error rather than this one -- a failure
  /// here is a secondary symptom.
  Future<String?> _discoverModel(String apiKey) async {
    try {
      final response = await _client.get(
        Uri.parse('$_apiBase/models?key=$apiKey'),
      );
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final models = (json['models'] as List?) ?? const [];

      final usable = <String>[];
      for (final entry in models) {
        if (entry is! Map) continue;
        final methods =
            (entry['supportedGenerationMethods'] as List?)?.cast<Object?>() ??
            const [];
        if (!methods.contains('generateContent')) continue;
        // "models/gemini-2.5-flash" -> "gemini-2.5-flash"
        final name = (entry['name'] as String? ?? '').split('/').last;
        if (name.isNotEmpty) usable.add(name);
      }
      if (usable.isEmpty) return null;

      // Prefer flash, then anything else, and avoid the embedding-only and
      // preview models where a stable one exists.
      usable.sort((a, b) {
        int rank(String m) {
          if (m.contains('flash') && !m.contains('preview')) return 0;
          if (m.contains('flash')) return 1;
          if (m.contains('pro') && !m.contains('preview')) return 2;
          return 3;
        }

        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : a.compareTo(b);
      });
      return usable.first;
    } catch (_) {
      return null;
    }
  }

  String _errorMessage(http.Response response) {
    var message = 'Failed to analyze image (HTTP ${response.statusCode})';
    try {
      final errJson = jsonDecode(response.body);
      if (errJson is Map &&
          errJson.containsKey('error') &&
          errJson['error'] is Map) {
        message = errJson['error']['message'] ?? message;
      }
    } catch (_) {}
    return message;
  }

  List<String> _parseMedicines(String responseBody) {
    final responseJson = jsonDecode(responseBody) as Map<String, dynamic>;
    final candidates = responseJson['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('No response generated by Gemini API.');
    }

    final firstCandidate = candidates.first as Map<String, dynamic>;
    final content = firstCandidate['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) {
      throw Exception('Could not extract text from Gemini response.');
    }

    final rawText = parts.first['text'] as String? ?? '';

    // Parse medicine names from comma/newline separated text
    return rawText
        .split(RegExp(r'[,;\n]'))
        .map((name) => name.replaceAll(RegExp(r'^[\d\.\*\-\s]+'), '').trim())
        .where((name) => name.isNotEmpty)
        .toList();
  }
}
