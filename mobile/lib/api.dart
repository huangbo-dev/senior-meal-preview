import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Client contract for communicating with the Senior Meal Preview Rust API.
abstract interface class MealApi {
  /// Fetches the dish and serving-change catalog from `GET /api/v1/catalog`.
  Future<Catalog> fetchCatalog();

  /// Requests a meal preview from `POST /api/v1/preview`.
  Future<MealPreview> preview({
    required String dishId,
    required List<String> changeIds,
    required MealPreferences preferences,
    String renderMode = 'illustrative_only',
  });

  /// Releases any underlying HTTP client resources.
  void close();
}

/// User-facing exception thrown when an API request fails or returns invalid data.
class ApiException implements Exception {
  /// Creates an [ApiException] with a plain-language [message].
  const ApiException(this.message);

  /// Actionable error message safe to display in a notice banner.
  final String message;

  @override
  String toString() => message;
}

/// Production [MealApi] backed by `package:http`.
class HttpMealApi implements MealApi {
  /// Creates an [HttpMealApi] configured via `--dart-define=API_BASE_URL` and
  /// optional `--dart-define=API_AUTH_TOKEN`.
  HttpMealApi({
    String baseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8787',
    ),
    String authToken = const String.fromEnvironment('API_AUTH_TOKEN'),
    http.Client? client,
    this.timeout = const Duration(seconds: 28),
  }) : _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
       _authToken = authToken.trim(),
       _client = client ?? http.Client();

  final String _baseUrl;
  final String _authToken;
  final http.Client _client;

  /// Maximum duration to wait for a single HTTP request before failing.
  final Duration timeout;

  Map<String, String> _headers({bool jsonBody = false}) => {
    if (jsonBody) 'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (_authToken.isNotEmpty) 'Authorization': 'Bearer $_authToken',
  };

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
    () => _client.get(_endpoint('/api/v1/catalog'), headers: _headers()),
    Catalog.fromJson,
  );

  @override
  Future<MealPreview> preview({
    required String dishId,
    required List<String> changeIds,
    required MealPreferences preferences,
    String renderMode = 'illustrative_only',
  }) async {
    if (changeIds.isEmpty ||
        changeIds.length > 2 ||
        changeIds.toSet().length != changeIds.length) {
      throw const ApiException('Choose one or two different changes.');
    }
    return _perform(
      () => _client.post(
        _endpoint('/api/v1/preview'),
        headers: _headers(jsonBody: true),
        body: jsonEncode({
          'dish_id': dishId,
          'change_ids': changeIds,
          'preferences': preferences.toJson(),
          if (renderMode != 'illustrative_only') 'render_mode': renderMode,
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
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(_errorMessage(response));
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
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

  /// Extracts a plain-language message for a non-2xx [response].
  ///
  /// Uses the API's structured `error.message` field when present; non-JSON
  /// gateway responses fall back to a status-based message.
  static String _errorMessage(http.Response response) {
    try {
      if (jsonDecode(response.body) case {
        'error': {'message': final String message},
      } when message.isNotEmpty) {
        return message;
      }
    } on FormatException {
      // Fall through to a status-based message.
    }
    return response.statusCode == 408
        ? 'The local service took too long. Check that it is running, then try again.'
        : 'The local service could not complete this request. Please try again.';
  }

  @override
  void close() => _client.close();
}
