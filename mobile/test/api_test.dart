import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:senior_meal_preview/api.dart';
import 'package:senior_meal_preview/models.dart';

import 'fixtures.dart';

void main() {
  test('web defaults to page origin without retaining route or query', () {
    expect(
      resolveApiBaseUrl(
        '',
        Uri.parse('https://preview.example.org/meal?x=1#step'),
      ),
      'https://preview.example.org',
    );
    expect(
      resolveApiBaseUrl('', Uri.parse('http://localhost:5173/')),
      'http://localhost:5173',
    );
  });

  test('explicit API origin wins and native development stays on loopback', () {
    expect(
      resolveApiBaseUrl(
        ' https://api.example.org/ ',
        Uri.parse('https://app.example.org'),
      ),
      'https://api.example.org',
    );
    expect(
      resolveApiBaseUrl('', Uri.parse('file:///app')),
      'http://127.0.0.1:8787',
    );
  });

  test(
    'catalog uses the configured local endpoint and decodes schema',
    () async {
      final api = HttpMealApi(
        baseUrl: 'http://127.0.0.1:8787/',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.toString(),
            'http://127.0.0.1:8787/api/v1/catalog',
          );
          return http.Response(jsonEncode(catalogJson), 200);
        }),
      );
      addTearDown(api.close);
      expect((await api.fetchCatalog()).dishes.length, 3);
    },
  );

  test('preview sends only IDs and in-memory preferences', () async {
    final api = HttpMealApi(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.headers['content-type'], contains('application/json'));
        expect(jsonDecode(request.body), {
          'dish_id': 'chicken_rice',
          'change_ids': ['extra_vegetables'],
          'preferences': {'texture': 'soft', 'flavour': 'mild'},
        });
        return http.Response(
          jsonEncode(
            previewJson(
              preferences: const MealPreferences(
                texture: 'soft',
                flavour: 'mild',
              ),
            ),
          ),
          200,
        );
      }),
    );
    addTearDown(api.close);
    final result = await api.preview(
      dishId: 'chicken_rice',
      changeIds: ['extra_vegetables'],
      preferences: const MealPreferences(texture: 'soft', flavour: 'mild'),
    );
    expect(result.preferences.texture, 'soft');
    expect(result.targets.single.id, 'extra_vegetables');
  });

  test('invalid change count and duplicates never hit the network', () async {
    final api = HttpMealApi(
      client: MockClient((_) async => throw StateError('Should not send')),
    );
    addTearDown(api.close);
    for (final changes in <List<String>>[
      [],
      ['a', 'b', 'c'],
      ['a', 'a'],
    ]) {
      await expectLater(
        api.preview(
          dishId: 'chicken_rice',
          changeIds: changes,
          preferences: const MealPreferences(),
        ),
        throwsA(isA<ApiException>()),
      );
    }
  });

  test('API validation errors retain the useful message', () async {
    final api = HttpMealApi(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'code': 'invalid_change',
              'message': 'This change is not available for fish soup.',
            },
          }),
          400,
        ),
      ),
    );
    addTearDown(api.close);
    await expectLater(
      api.fetchCatalog(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('fish soup'),
        ),
      ),
    );
  });

  test('network failures produce an actionable connection error', () async {
    final api = HttpMealApi(
      client: MockClient((_) async => throw http.ClientException('network')),
    );
    addTearDown(api.close);
    await expectLater(
      api.fetchCatalog(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('Check your internet connection'),
        ),
      ),
    );
  });

  test('requests time out instead of waiting forever', () async {
    final api = HttpMealApi(
      timeout: const Duration(milliseconds: 5),
      client: MockClient((_) => Completer<http.Response>().future),
    );
    addTearDown(api.close);
    await expectLater(
      api.fetchCatalog(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('too long'),
        ),
      ),
    );
  });

  test('malformed and unsupported responses fail closed', () async {
    for (final body in [
      'not json',
      '[]',
      '{}',
      jsonEncode({...catalogJson, 'mode': 'model_output'}),
      jsonEncode({...catalogJson, 'schema_version': 2}),
    ]) {
      final api = HttpMealApi(
        client: MockClient((_) async => http.Response(body, 200)),
      );
      await expectLater(api.fetchCatalog(), throwsA(isA<ApiException>()));
      api.close();
    }
  });

  test('empty or duplicate catalogs are rejected', () {
    expect(
      () => Catalog.fromJson({...catalogJson, 'dishes': <Object>[]}),
      throwsFormatException,
    );
    expect(
      () => Catalog.fromJson({
        ...catalogJson,
        'dishes': [
          (catalogJson['dishes'] as List).first,
          (catalogJson['dishes'] as List).first,
        ],
      }),
      throwsFormatException,
    );
  });

  test('duplicate preview targets are rejected at the response boundary', () {
    final body = previewJson();
    body['edit_targets'] = [
      (body['edit_targets'] as List).single,
      (body['edit_targets'] as List).single,
    ];
    expect(() => MealPreview.fromJson(body), throwsFormatException);
  });

  test('unsafe API URL forms are rejected before network access', () async {
    for (final base in [
      'file:///tmp/demo',
      'http://user:secret@localhost:8787',
      'http://localhost:8787?token=test',
    ]) {
      final api = HttpMealApi(
        baseUrl: base,
        client: MockClient((_) async => throw StateError('Should not send')),
      );
      await expectLater(api.fetchCatalog(), throwsA(isA<ApiException>()));
      api.close();
    }
  });

  test('catalog decodes selection rules and supports legacy v1 catalogs', () {
    final decoded = Catalog.fromJson(catalogJson);
    expect(decoded.selection.minChanges, 1);
    expect(decoded.selection.maxChanges, 2);
    expect(decoded.selection.maxFor(1), 1);
    expect(decoded.selection.maxFor(3), 2);
    expect(decoded.changesFor('fish_soup').map((c) => c.id), [
      'extra_vegetables',
    ]);

    final legacyJson = Map<String, dynamic>.of(catalogJson)
      ..remove('selection');
    final legacy = Catalog.fromJson(legacyJson);
    expect(legacy.selection.minChanges, 1);
    expect(legacy.selection.maxChanges, 2);

    for (final invalidSelection in [
      {'min_changes': 0, 'max_changes': 2},
      {'min_changes': 2, 'max_changes': 1},
      {'min_changes': 1, 'max_changes': 3},
    ]) {
      expect(
        () => Catalog.fromJson({...catalogJson, 'selection': invalidSelection}),
        throwsFormatException,
      );
    }
  });

  test(
    'non-JSON error responses report service errors rather than schema mismatch',
    () async {
      final timeoutApi = HttpMealApi(
        client: MockClient((_) async => http.Response('', 408)),
      );
      addTearDown(timeoutApi.close);
      await expectLater(
        timeoutApi.fetchCatalog(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('taking too long'),
          ),
        ),
      );

      final errorApi = HttpMealApi(
        client: MockClient((_) async => http.Response('Bad gateway', 502)),
      );
      addTearDown(errorApi.close);
      await expectLater(
        errorApi.fetchCatalog(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('did not work'),
          ),
        ),
      );
    },
  );
}
