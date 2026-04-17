import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/tap_models.dart';
import 'auth_service.dart';

class TapService {
  final AuthService _auth;
  TapService(this._auth);

  Future<TapResult> generateTap({
    required String targetUpn,
    required int lifetimeInMinutes,
  }) async {
    final token = await _auth.getAccessTokenAsync();
    if (token == null) {
      throw Exception('Not authenticated. Please sign in again.');
    }

    final response = await http.post(
      Uri.parse(AppConfig.tapEndpoint),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'targetUpn': targetUpn,
        'lifetimeInMinutes': lifetimeInMinutes,
      }),
    );

    final contentType = response.headers['content-type'] ?? '';
    Map<String, dynamic> body = {};
    bool isJson = false;
    if (response.body.isNotEmpty) {
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
        isJson = true;
      } catch (_) {}
    }

    // If the server returned HTML instead of JSON the request hit the wrong endpoint.
    if (!isJson && response.statusCode == 200) {
      final snippet =
          response.body.substring(0, response.body.length.clamp(0, 200));
      if (response.body.isEmpty) {
        throw Exception(
            'API returned 200 with an empty body. URL called: ${AppConfig.tapEndpoint}\n'
            'Content-Type: ${contentType.isEmpty ? "missing" : contentType}. '
            'This is not a valid TAP response.');
      }

      throw Exception(
          'API returned non-JSON response. URL called: ${AppConfig.tapEndpoint}\n'
          'Content-Type: ${contentType.isEmpty ? "missing" : contentType}\n'
          'First 200 chars: $snippet');
    }

    switch (response.statusCode) {
      case 200:
        return TapResult.fromJson(body);
      case 400:
        throw Exception(body['error'] ?? 'Invalid request.');
      case 401:
        final msg = body['error'] ?? body['message'] ?? '';
        throw Exception(
            'Unauthorized (401)${msg.isNotEmpty ? ": $msg" : ""}. '
            'Your token may be missing the TAP.Generator role or your session has expired.');
      case 403:
        throw Exception(
            body['error'] ?? 'Forbidden. You may lack the TAP.Generator role or the target user is privileged.');
      case 404:
        throw Exception(body['error'] ?? 'Target user not found.');
      default:
        final detail = body['error'] ?? body['message'] ?? response.body;
        throw Exception('Unexpected error (${response.statusCode}): $detail');
    }
  }
}
