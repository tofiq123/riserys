import 'package:collection/collection.dart';

import 'crew_member.dart';

/// The signed-in user's crew: accepted [friends], [incoming] pending requests
/// (they asked; you accept/decline), and [outgoing] pending requests (you asked;
/// you can cancel). Immutable snapshot; see `CrewService`.
class CrewState {
  const CrewState({
    this.friends = const [],
    this.incoming = const [],
    this.outgoing = const [],
  });

  static const empty = CrewState();

  final List<CrewMember> friends;
  final List<CrewMember> incoming;
  final List<CrewMember> outgoing;

  bool get isEmpty =>
      friends.isEmpty && incoming.isEmpty && outgoing.isEmpty;

  CrewState copyWith({
    List<CrewMember>? friends,
    List<CrewMember>? incoming,
    List<CrewMember>? outgoing,
  }) =>
      CrewState(
        friends: friends ?? this.friends,
        incoming: incoming ?? this.incoming,
        outgoing: outgoing ?? this.outgoing,
      );

  static const _eq = ListEquality<CrewMember>();

  @override
  bool operator ==(Object other) =>
      other is CrewState &&
      _eq.equals(other.friends, friends) &&
      _eq.equals(other.incoming, incoming) &&
      _eq.equals(other.outgoing, outgoing);

  @override
  int get hashCode =>
      Object.hash(_eq.hash(friends), _eq.hash(incoming), _eq.hash(outgoing));
}
