typedef PartyId = String;
typedef InteractionId = String;

enum CommunicationMethod { phone, email, sms, letter, chat, other }

enum FollowUpStatus { open, completed }

/// Where an open follow-up sits relative to "now" (#34).
enum FollowUpUrgency { overdue, today, upcoming }

class Party {
  const Party({required this.id, required this.name});
  final PartyId id;
  final String name;
}

class FollowUp {
  const FollowUp({
    required this.dueAt,
    this.status = FollowUpStatus.open,
    this.hasTime = false,
  });

  /// For a day-only follow-up ([hasTime] false) this is local midnight at the
  /// start of the due day; the item is treated as due at the end of that day.
  final DateTime dueAt;
  final FollowUpStatus status;
  final bool hasTime;

  FollowUp complete() => FollowUp(
    dueAt: dueAt,
    status: FollowUpStatus.completed,
    hasTime: hasTime,
  );

  /// The moment the follow-up becomes overdue.
  DateTime get effectiveDueAt {
    if (hasTime) return dueAt;
    final local = dueAt.toLocal();
    return DateTime(local.year, local.month, local.day + 1);
  }

  FollowUpUrgency urgency(DateTime now) {
    final localNow = now.toLocal();
    if (!effectiveDueAt.isAfter(localNow)) return FollowUpUrgency.overdue;
    final due = dueAt.toLocal();
    final sameDay =
        due.year == localNow.year &&
        due.month == localNow.month &&
        due.day == localNow.day;
    return sameDay ? FollowUpUrgency.today : FollowUpUrgency.upcoming;
  }
}

class Interaction {
  const Interaction({
    required this.id,
    required this.partyId,
    required this.summary,
    required this.timestamp,
    required this.createdAt,
    this.method = CommunicationMethod.phone,
    this.contactName,
    this.referenceNumbers = const [],
    this.commitment,
    this.followUp,
  });
  final InteractionId id;
  final PartyId partyId;
  final String summary;
  final DateTime timestamp;
  final DateTime createdAt;
  final CommunicationMethod method;
  final String? contactName;
  final List<String> referenceNumbers;
  final String? commitment;
  final FollowUp? followUp;
  Interaction copyWith({
    PartyId? partyId,
    String? summary,
    DateTime? createdAt,
    FollowUp? followUp,
  }) => Interaction(
    id: id,
    partyId: partyId ?? this.partyId,
    summary: summary ?? this.summary,
    timestamp: timestamp,
    createdAt: createdAt ?? this.createdAt,
    method: method,
    contactName: contactName,
    referenceNumbers: referenceNumbers,
    commitment: commitment,
    followUp: followUp ?? this.followUp,
  );
}

/// An interaction together with its party, as shown in the home list.
class InteractionEntry {
  const InteractionEntry({required this.party, required this.interaction});
  final Party party;
  final Interaction interaction;
}

/// Keyset position for paging the newest-first interaction list.
class RecentCursor {
  const RecentCursor({required this.timestamp, required this.id});
  RecentCursor.after(Interaction last)
    : timestamp = last.timestamp,
      id = last.id;
  final DateTime timestamp;
  final InteractionId id;
}

class CreateInteractionCommand {
  const CreateInteractionCommand({
    required this.partyName,
    required this.summary,
    this.followUpDueAt,
    this.followUpHasTime = false,
    this.timestamp,
    this.method = CommunicationMethod.phone,
    this.contactName,
    this.referenceNumbers = const [],
    this.commitment,
  });
  final String partyName;
  final String summary;
  final DateTime? followUpDueAt;
  final bool followUpHasTime;
  final DateTime? timestamp;
  final CommunicationMethod method;
  final String? contactName;
  final List<String> referenceNumbers;
  final String? commitment;
}

class UpdateInteractionCommand {
  const UpdateInteractionCommand({
    required this.interaction,
    required this.summary,
    this.targetPartyName,
  });
  final Interaction interaction;
  final String summary;

  /// When set, the interaction moves to this party (found or created by name).
  /// The interaction ID and creation timestamp are kept (#33).
  final String? targetPartyName;
}

/// Thrown when a rename would collide with another party's name.
class PartyNameConflict implements Exception {
  const PartyNameConflict(this.existing);
  final Party existing;
  @override
  String toString() => 'A party named "${existing.name}" already exists';
}
