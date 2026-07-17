/// An authenticated Rise account. This is optional and purely additive:
/// nothing on the alarm/ring/snooze/stats path depends on it. A null
/// [username] means the account has not yet been claimed and routes the UI
/// to the claim screen.
class RiseAccount {
  const RiseAccount({
    required this.id,
    required this.displayName,
    required this.avatarColor,
    this.username,
    this.email,
  });

  /// Supabase auth user id (uuid string).
  final String id;

  /// Null until claimed; null routes UI to the claim screen.
  final String? username;

  /// Shown name; server default `''`.
  final String displayName;

  /// Hex `'#RRGGBB'` string; UI resolves to a Color later.
  final String avatarColor;

  /// Google email if available.
  final String? email;

  bool get needsUsername => username == null;

  RiseAccount copyWith({
    String? id,
    String? username,
    String? displayName,
    String? avatarColor,
    String? email,
  }) =>
      RiseAccount(
        id: id ?? this.id,
        username: username ?? this.username,
        displayName: displayName ?? this.displayName,
        avatarColor: avatarColor ?? this.avatarColor,
        email: email ?? this.email,
      );

  @override
  bool operator ==(Object other) =>
      other is RiseAccount &&
      other.id == id &&
      other.username == username &&
      other.displayName == displayName &&
      other.avatarColor == avatarColor &&
      other.email == email;

  @override
  int get hashCode =>
      Object.hash(id, username, displayName, avatarColor, email);
}
