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

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    switch (response.statusCode) {
      case 200:
        return TapResult.fromJson(body);
      case 400:
        throw Exception(body['error'] ?? 'Invalid request.');
      case 401:
        throw Exception('Session expired. Please reload the page to sign in.');
      case 403:
        throw Exception(
            body['error'] ?? 'Forbidden. You may lack the TAP.Generator role or the target user is privileged.');
      case 404:
        throw Exception(body['error'] ?? 'Target user not found.');
      default:
        throw Exception(
            'Unexpected error (${response.statusCode}): ${body['error'] ?? response.body}');
    }
  }
}
