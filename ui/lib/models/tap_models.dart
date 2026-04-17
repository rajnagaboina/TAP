class UserInfo {
  final String upn;
  final String displayName;

  const UserInfo({required this.upn, required this.displayName});

  factory UserInfo.fromClaims(List<dynamic> claims) {
    String find(String type) =>
        (claims.firstWhere((c) => c['typ'] == type,
                orElse: () => {'val': ''})['val'] as String?) ??
        '';

    return UserInfo(
      upn: find('preferred_username').isEmpty
          ? find('http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn')
          : find('preferred_username'),
      displayName: find('name'),
    );
  }
}

class TapResult {
  final String temporaryAccessPass;
  final int lifetimeInMinutes;
  final DateTime? startDateTime;
  final bool isUsableOnce;

  const TapResult({
    required this.temporaryAccessPass,
    required this.lifetimeInMinutes,
    this.startDateTime,
    required this.isUsableOnce,
  });

  factory TapResult.fromJson(Map<String, dynamic> json) => TapResult(
        temporaryAccessPass: json['temporaryAccessPass'] as String,
        lifetimeInMinutes: json['lifetimeInMinutes'] as int,
        startDateTime: json['startDateTime'] != null
            ? DateTime.parse(json['startDateTime'] as String)
            : null,
        isUsableOnce: json['isUsableOnce'] as bool? ?? true,
      );
}
