import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

  
const String _baseUrl = 'http://192.168.1.33:8000'; // 

class ApiService {
  static final _client = http.Client();
  static const _headers = {'Content-Type': 'application/json'};

  // ── /classify ──────────────────────────────────────────
  static Future<Map<String, dynamic>> classify(String message) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$_baseUrl/classify'),
            headers: _headers,
            body: jsonEncode({
              'sms_text': message,
              'message': message, // backward compatibility
            }),
          )
          .timeout(const Duration(seconds: 15));
      _assertOk(res);
      return _decode(res);
    } on TimeoutException catch (_) {
      throw const ApiException(
        statusCode: 408,
        message: 'Connection timed out. Please check if the Python backend is running at $_baseUrl.',
      );
    } catch (e) {
      throw ApiException(
        statusCode: 503,
        message: 'Failed to connect to backend at $_baseUrl: $e',
      );
    }
  }

  // ── /manual-category ───────────────────────────────────
  static Future<Map<String, dynamic>> manualCategory({
    required String message,
    required String category,
    required double amount,
    required String receiver,
    required String cleanText,
  }) async {
    final res = await _client
        .post(
          Uri.parse('$_baseUrl/manual-category'),
          headers: _headers,
          body: jsonEncode({
            'message': message,
            'category': category,
            'amount': amount,
            'receiver': receiver,
            'clean_text': cleanText,
          }),
        )
        .timeout(const Duration(seconds: 15));
    _assertOk(res);
    return _decode(res);
  }

  // ── /add-category ──────────────────────────────────────
  static Future<Map<String, dynamic>> addCategory(String category) async {
    final res = await _client
        .post(
          Uri.parse('$_baseUrl/add-category'),
          headers: _headers,
          body: jsonEncode({'category': category}),
        )
        .timeout(const Duration(seconds: 10));
    _assertOk(res);
    return _decode(res);
  }

  // ── GET /transactions ──────────────────────────────────
  static Future<Map<String, dynamic>> getTransactions({
    String? category,
    int limit = 50,
  }) async {
    final params = <String, String>{'limit': limit.toString()};
    if (category != null && category.isNotEmpty) params['category'] = category;
    final uri = Uri.parse('$_baseUrl/transactions').replace(queryParameters: params);
    final res = await _client.get(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));
    _assertOk(res);
    return _decode(res);
  }

  // ── GET /summary ───────────────────────────────────────
  static Future<Map<String, dynamic>> getSummary() async {
    final res = await _client
        .get(Uri.parse('$_baseUrl/summary'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    _assertOk(res);
    return _decode(res);
  }

  // ── POST /retrain-model ────────────────────────────────
  static Future<Map<String, dynamic>> retrainModel() async {
    final res = await _client
        .post(Uri.parse('$_baseUrl/retrain-model'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    _assertOk(res);
    return _decode(res);
  }

  // ── /login ─────────────────────────────────────────────
  static Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await _client
        .post(
          Uri.parse('$_baseUrl/login'),
          headers: _headers,
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 15));
    _assertOk(res);
    return _decode(res);
  }

  // ── /signup ────────────────────────────────────────────
  static Future<Map<String, dynamic>> signup(String name, String email, String password) async {
    final res = await _client
        .post(
          Uri.parse('$_baseUrl/signup'),
          headers: _headers,
          body: jsonEncode({'name': name, 'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 15));
    _assertOk(res);
    return _decode(res);
  }

  static Map<String, dynamic> _decode(http.Response res) =>
      jsonDecode(res.body) as Map<String, dynamic>;

  static void _assertOk(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final body = _tryDecode(res.body);
      throw ApiException(
        statusCode: res.statusCode,
        message: body?['detail'] ?? body?['message'] ?? res.body,
      );
    }
  }

  static Map<String, dynamic>? _tryDecode(String body) {
    try { return jsonDecode(body) as Map<String, dynamic>; }
    catch (_) { return null; }
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'ApiException($statusCode): $message';

  String get userMessage {
    switch (statusCode) {
      case 401: return 'Invalid credentials. Please try again.';
      case 404: return 'Resource not found.';
      case 422: return 'Invalid input: $message';
      case 500: return 'Server error. Is the Python backend running?';
      default: return message.isNotEmpty ? message : 'Something went wrong.';
    }
  }
}