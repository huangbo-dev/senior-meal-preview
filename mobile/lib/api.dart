import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

abstract interface class MealApi {
  Future<Catalog> fetchCatalog();
  Future<MealPreview> preview({
    required String dishId,
    required List<String> changeIds,
    required MealPreferences preferences,
  });
  void close();
}

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class HttpMealApi implements MealApi {
  HttpMealApi({
    String baseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8787',
    ),
    http.Client? client,
    this.timeout = const Duration(seconds: 12),
  }) : _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
       _client = client ?? http.Client();
  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  Uri _endpoint(String path) {
    final uri = Uri.parse('$_baseUrl$path');
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const ApiException(
        'The API address is not valid. Check API_BASE_URL.',
      );
    }
    return uri;
  }

  @override
  Future<Catalog> fetchCatalog() => _perform(
    () => _client.get(
      _endpoint('/api/v1/catalog'),
      headers: {'Accept': 'application/json'},
    ),
    Catalog.fromJson,
  );

  @override
  Future<MealPreview> preview({
    required String dishId,
    required List<String> changeIds,
    required MealPreferences preferences,
  }) async {
    if (changeIds.isEmpty ||
        changeIds.length > 2 ||
        changeIds.toSet().length != changeIds.length) {
      throw const ApiException('Choose one or two different changes.');
    }
    return _perform(
      () => _client.post(
        _endpoint('/api/v1/preview'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'dish_id': dishId,
          'change_ids': changeIds,
          'preferences': preferences.toJson(),
        }),
      ),
      MealPreview.fromJson,
    );
  }

  Future<T> _perform<T>(
    Future<http.Response> Function() request,
    T Function(Map<String, dynamic>) decode,
  ) async {
    try {
      final response = await request().timeout(timeout);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = body['error'];
        final message = error is Map ? error['message'] : null;
        throw ApiException(
          message is String && message.isNotEmpty
              ? message
              : 'The local service could not complete this request. Please try again.',
        );
      }
      return decode(body);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        'The local service took too long. Check that it is running, then try again.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Cannot reach the local service. Start the Rust API and check the API address, then try again.',
      );
    } on FormatException {
      throw const ApiException(
        'The local service returned an unreadable response. Check that the API versions match.',
      );
    } on TypeError {
      throw const ApiException(
        'The local service returned an unexpected response. Check that the API versions match.',
      );
    }
  }

  @override
  void close() => _client.close();
}
