import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;
import '../models/tap_models.dart';

// Easy Auth provides authentication at the App Service platform level.
// The Flutter app reads the session from /.auth/me (user info + access token).
// When unauthenticated, we redirect the browser to /.auth/login/aad.
class AuthService extends ChangeNotifier {
  UserInfo? _currentUser;
  String? _accessToken;

  UserInfo? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;

  Future<void> initAsync() async {
    try {
      final meResponse = await http.get(Uri.parse('/.auth/me'));
      if (meResponse.statusCode == 200) {
        final data = jsonDecode(meResponse.body) as List<dynamic>;
        if (data.isNotEmpty) {
          final entry = data[0] as Map<String, dynamic>;
          final claims = (entry['user_claims'] as List<dynamic>?) ?? [];
          _currentUser = UserInfo.fromClaims(claims);
          _accessToken = entry['access_token'] as String?;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('AuthService.initAsync error: $e');
    }
  }

  Future<String?> getAccessTokenAsync() async {
    if (_accessToken != null) return _accessToken;
    try {
      await http.get(Uri.parse('/.auth/refresh'));
      await initAsync();
      return _accessToken;
    } catch (e) {
      debugPrint('AuthService.getAccessTokenAsync error: $e');
    }
    return null;
  }

  void redirectToLogin() {
    final redirectUrl = Uri.encodeFull(web.window.location.href);
    web.window.location.replace('/.auth/login/aad?post_login_redirect_url=$redirectUrl');
  }

  void signOut() {
    _currentUser = null;
    _accessToken = null;
    notifyListeners();
    web.window.location.replace('/.auth/logout?post_logout_redirect_uri=/');
  }
}
