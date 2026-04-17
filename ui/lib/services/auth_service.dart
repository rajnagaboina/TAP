import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/tap_models.dart';

// Easy Auth provides authentication at the App Service platform level.
// The Flutter app reads the session from /.auth/me and requests an API
// token via /.auth/token – no MSAL library needed in the Flutter code.
class AuthService extends ChangeNotifier {
  UserInfo? _currentUser;
  String? _accessToken;

  UserInfo? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;

  // Call once at app startup.
  Future<void> initAsync() async {
    try {
      final meResponse = await http.get(Uri.parse('/.auth/me'));
      if (meResponse.statusCode == 200) {
        final data = jsonDecode(meResponse.body) as List<dynamic>;
        if (data.isNotEmpty) {
          final claims =
              (data[0]['user_claims'] as List<dynamic>?) ?? [];
          _currentUser = UserInfo.fromClaims(claims);
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('AuthService.initAsync error: $e');
    }
  }

  // Gets (or refreshes) the Bearer token for the API audience.
  // Easy Auth stores the token in the server-side token store and issues it
  // when the app calls /.auth/token.
  Future<String?> getAccessTokenAsync() async {
    try {
      final response = await http.get(Uri.parse('/.auth/token'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _accessToken = data['access_token'] as String?;
        return _accessToken;
      }
    } catch (e) {
      debugPrint('AuthService.getAccessTokenAsync error: $e');
    }
    return null;
  }

  void signOut() {
    _currentUser = null;
    _accessToken = null;
    notifyListeners();
  }
}
