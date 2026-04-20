// Values injected at build time via --dart-define (set in GitHub Actions).
// See azure-config.yaml for where to obtain each value.
class AppConfig {
  // APIM gateway URL  e.g. https://apim-tap-prod.azure-api.net
  static const String apimBaseUrl =
      String.fromEnvironment('APIM_BASE_URL', defaultValue: '');

  // TAP Generator API path on APIM
  static const String tapApiPath = '/tap/api/tap';
  static const String usersSearchApiPath = '/tap/api/users/search';

  static String get tapEndpoint => '$apimBaseUrl$tapApiPath';
  static String get usersSearchEndpoint => '$apimBaseUrl$usersSearchApiPath';

  // Entra tenant & app IDs – used to construct the /.auth/token call
  static const String tenantId =
      String.fromEnvironment('TENANT_ID', defaultValue: '');

  static const String uiClientId =
      String.fromEnvironment('UI_CLIENT_ID', defaultValue: '');

  static const String apiClientId =
      String.fromEnvironment('API_CLIENT_ID', defaultValue: '');

  // Audience the Flutter app requests a token for (the API App Registration)
  static String get apiAudience => 'api://$apiClientId';
}
