/// A group the signed-in user belongs to. [role] is the *user's own* role in the
/// group ('owner' or 'member'); [inviteCode] is the share code others join with.
/// [memberCount] is optional (null when not loaded).
class Group {
  const Group({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.ownerId,
    required this.role,
    this.memberCount,
  });

  final String id;
  final String name;

  /// The uppercase alphanumeric code others use to join.
  final String inviteCode;

  /// Auth id of the group's owner (source of truth for ownership).
  final String ownerId;

  /// The signed-in user's role in this group: 'owner' or 'member'.
  final String role;

  final int? memberCount;

  bool get isOwner => role == 'owner';

  Group copyWith({
    String? id,
    String? name,
    String? inviteCode,
    String? ownerId,
    String? role,
    int? memberCount,
  }) =>
      Group(
        id: id ?? this.id,
        name: name ?? this.name,
        inviteCode: inviteCode ?? this.inviteCode,
        ownerId: ownerId ?? this.ownerId,
        role: role ?? this.role,
        memberCount: memberCount ?? this.memberCount,
      );

  @override
  bool operator ==(Object other) =>
      other is Group &&
      other.id == id &&
      other.name == name &&
      other.inviteCode == inviteCode &&
      other.ownerId == ownerId &&
      other.role == role &&
      other.memberCount == memberCount;

  @override
  int get hashCode =>
      Object.hash(id, name, inviteCode, ownerId, role, memberCount);

  @override
  String toString() => 'Group(id: $id, name: $name, role: $role)';
}

/// Orders groups for display: alphabetical by name (case-insensitive), with the
/// group id as a stable tiebreak. Pure; returns a new list, never mutates input.
List<Group> sortGroups(List<Group> input) {
  final list = [...input];
  list.sort((a, b) {
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (byName != 0) return byName;
    return a.id.compareTo(b.id);
  });
  return list;
}
