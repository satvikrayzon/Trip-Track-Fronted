import 'dart:convert';

/// Decodes JWT payload (no signature verification — for client hints only).
abstract final class JwtPayload {
  static Map<String, dynamic>? decode(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      final json = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final map = jsonDecode(json);
      if (map is! Map) return null;
      return Map<String, dynamic>.from(map);
    } catch (_) {
      return null;
    }
  }

  /// Typical Nest JWT: `sub` or custom `uid` claim.
  static String? userId(String jwt) {
    final m = decode(jwt);
    if (m == null) return null;
    final v = m['uid'] ?? m['sub'];
    if (v == null) return null;
    return v.toString();
  }

  /// Role claim from JWT (`role` or `userRole`).
  static String? role(String jwt) {
    final m = decode(jwt);
    if (m == null) return null;
    final v = m['role'] ?? m['userRole'];
    if (v == null) return null;
    return v.toString().toLowerCase();
  }

  /// True when JWT `exp` is in the past (with optional leeway).
  static bool isExpired(
    String jwt, {
    Duration leeway = const Duration(seconds: 30),
  }) {
    final m = decode(jwt);
    if (m == null) return true;
    final exp = m['exp'];
    if (exp is! num) return false;
    final expiry =
        DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true);
    return DateTime.now().toUtc().add(leeway).isAfter(expiry);
  }
}
