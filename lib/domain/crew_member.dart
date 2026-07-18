/// The public view of another user in your crew: an accepted friend, or the
/// other party in a pending friend request (incoming or outgoing).
class CrewMember {
  const CrewMember({
    required this.id,
    required this.username,
    required this.displayName,
    required this.avatarColor,
  });

  /// The other user's auth id.
  final String id;

  /// Their claimed handle (lowercased).
  final String username;

  final String displayName;

  /// Hex '#RRGGBB'.
  final String avatarColor;

  CrewMember copyWith({
    String? id,
    String? username,
    String? displayName,
    String? avatarColor,
  }) =>
      CrewMember(
        id: id ?? this.id,
        username: username ?? this.username,
        displayName: displayName ?? this.displayName,
        avatarColor: avatarColor ?? this.avatarColor,
      );

  @override
  bool operator ==(Object other) =>
      other is CrewMember &&
      other.id == id &&
      other.username == username &&
      other.displayName == displayName &&
      other.avatarColor == avatarColor;

  @override
  int get hashCode => Object.hash(id, username, displayName, avatarColor);

  @override
  String toString() =>
      'CrewMember(id: $id, username: $username, displayName: $displayName, '
      'avatarColor: $avatarColor)';
}
