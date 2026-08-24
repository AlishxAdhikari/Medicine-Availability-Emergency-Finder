import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medalert/services/gemini_prescription_service.dart';

/// The scanner used to hardcode `gemini-1.5-flash`. Google retired that model
/// from v1beta and every scan started failing with "is not found for API
/// version v1beta", which looks like a bad API key rather than a name that no
/// longer exists. These cover the recovery: walk the known models, and if all
/// of them are gone, ask the API what it actually has.

final _image = Uint8List.fromList([1, 2, 3]);

String _okBody(String text) => jsonEncode({
  'candidates': [
    {
      'content': {
        'parts': [
          {'text': text},
        ],
      },
    },
  ],
});

String _notFound(String model) => jsonEncode({
  'error': {
    'code': 404,
    'message':
        'models/$model is not found for API version v1beta, or is not '
        'supported for generateContent.',
  },
});

/// The model name out of `.../models/<name>:generateContent`.
String _modelOf(Uri url) => url.pathSegments.last.split(':').first;

void main() {
  setUp(GeminiPrescriptionService.resetResolvedModelForTest);

  test('uses the first model that answers', () async {
    final tried = <String>[];
    GeminiPrescriptionService.instance.clientForTest = MockClient((
      request,
    ) async {
      tried.add(_modelOf(request.url));
      return http.Response(_okBody('Amoxicillin, Paracetamol'), 200);
    });

    final result = await GeminiPrescriptionService.instance
        .analyzePrescriptionImage(_image, overrideApiKey: 'k');

    expect(result, ['Amoxicillin', 'Paracetamol']);
    expect(tried, hasLength(1));
  });

  test('walks past a retired model to the next one', () async {
    final tried = <String>[];
    GeminiPrescriptionService.instance.clientForTest = MockClient((
      request,
    ) async {
      final model = _modelOf(request.url);
      tried.add(model);
      if (model == 'gemini-2.5-flash') {
        return http.Response(_notFound(model), 404);
      }
      return http.Response(_okBody('Metformin'), 200);
    });

    final result = await GeminiPrescriptionService.instance
        .analyzePrescriptionImage(_image, overrideApiKey: 'k');

    expect(result, ['Metformin']);
    expect(tried.length, greaterThan(1));
  });

  test('asks the API for a model when every known name is gone', () async {
    var listed = false;
    GeminiPrescriptionService.instance.clientForTest = MockClient((
      request,
    ) async {
      if (request.method == 'GET') {
        listed = true;
        return http.Response(
          jsonEncode({
            'models': [
              {
                'name': 'models/embedding-001',
                'supportedGenerationMethods': ['embedContent'],
              },
              {
                'name': 'models/gemini-9.9-flash',
                'supportedGenerationMethods': ['generateContent'],
              },
            ],
          }),
          200,
        );
      }
      if (_modelOf(request.url) == 'gemini-9.9-flash') {
        return http.Response(_okBody('Cetirizine'), 200);
      }
      return http.Response(_notFound(_modelOf(request.url)), 404);
    });

    final result = await GeminiPrescriptionService.instance
        .analyzePrescriptionImage(_image, overrideApiKey: 'k');

    expect(listed, isTrue);
    expect(result, ['Cetirizine']);
  });

  test('never offers a model that cannot generate content', () async {
    GeminiPrescriptionService.instance.clientForTest = MockClient((
      request,
    ) async {
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'models': [
              {
                'name': 'models/embedding-001',
                'supportedGenerationMethods': ['embedContent'],
              },
            ],
          }),
          200,
        );
      }
      return http.Response(_notFound(_modelOf(request.url)), 404);
    });

    expect(
      () => GeminiPrescriptionService.instance.analyzePrescriptionImage(
        _image,
        overrideApiKey: 'k',
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('No Gemini model'),
        ),
      ),
    );
  });

  test('reports a bad key immediately instead of trying every model', () async {
    var calls = 0;
    GeminiPrescriptionService.instance.clientForTest = MockClient((
      request,
    ) async {
      calls++;
      return http.Response(
        jsonEncode({
          'error': {'code': 400, 'message': 'API key not valid'},
        }),
        400,
      );
    });

    await expectLater(
      GeminiPrescriptionService.instance.analyzePrescriptionImage(
        _image,
        overrideApiKey: 'bad',
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('API key not valid'),
        ),
      ),
    );
    expect(calls, 1);
  });

  test('remembers the working model so the next scan is one call', () async {
    var generateCalls = 0;
    GeminiPrescriptionService.instance.clientForTest = MockClient((
      request,
    ) async {
      generateCalls++;
      final model = _modelOf(request.url);
      if (model == 'gemini-2.5-flash') {
        return http.Response(_notFound(model), 404);
      }
      return http.Response(_okBody('Omeprazole'), 200);
    });

    await GeminiPrescriptionService.instance.analyzePrescriptionImage(
      _image,
      overrideApiKey: 'k',
    );
    final afterFirst = generateCalls;

    await GeminiPrescriptionService.instance.analyzePrescriptionImage(
      _image,
      overrideApiKey: 'k',
    );

    expect(generateCalls - afterFirst, 1);
  });
}
