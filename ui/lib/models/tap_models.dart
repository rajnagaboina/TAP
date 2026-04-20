class UserInfo {
  final String upn;
  final String displayName;
  final List<String> roles;

  const UserInfo({
    required this.upn,
    required this.displayName,
    required this.roles,
  });

  bool get isTapGenerator => roles.contains('TAP.Generator');

  factory UserInfo.fromClaims(List<dynamic> claims) {
    String find(String type) =>
        (claims.firstWhere((c) => c['typ'] == type,
                orElse: () => {'val': ''})['val'] as String?) ??
        '';

    // Easy Auth returns roles under either the v2 short name or the v1 full URI
    const roleClaimTypes = {
      'roles',
      'http://schemas.microsoft.com/ws/2008/06/identity/claims/role',
    };
    final roles = claims
        .where((c) => roleClaimTypes.contains(c['typ']))
        .map<String>((c) => (c['val'] as String?) ?? '')
        .where((v) => v.isNotEmpty)
        .toList();

    return UserInfo(
      upn: find('preferred_username').isEmpty
          ? find('http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn')
          : find('preferred_username'),
      displayName: find('name'),
      roles: roles,
    );
  }
}

class UserSummary {
  final String displayName;
  final String givenName;
  final String surname;
  final String upn;

  const UserSummary({
    required this.displayName,
    required this.givenName,
    required this.surname,
    required this.upn,
  });

  String get fullName {
    final name = '${givenName.trim()} ${surname.trim()}'.trim();
    return name.isNotEmpty ? name : displayName;
  }

  factory UserSummary.fromJson(Map<String, dynamic> json) => UserSummary(
        displayName: (json['displayName'] ?? '') as String,
        givenName: (json['givenName'] ?? '') as String,
        surname: (json['surname'] ?? '') as String,
        upn: (json['upn'] ?? '') as String,
      );
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
        temporaryAccessPass: (json['temporaryAccessPass'] ?? json['TemporaryAccessPass'] ?? '') as String,
        lifetimeInMinutes: (json['lifetimeInMinutes'] ?? json['LifetimeInMinutes'] ?? 0) as int,
        startDateTime: (json['startDateTime'] ?? json['StartDateTime']) != null
            ? DateTime.parse((json['startDateTime'] ?? json['StartDateTime']) as String)
            : null,
        isUsableOnce: (json['isUsableOnce'] ?? json['IsUsableOnce'] ?? true) as bool,
      );
}
