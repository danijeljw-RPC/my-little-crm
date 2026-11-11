typedef PartyId = String;
typedef InteractionId = String;

enum CommunicationMethod { phone, email, sms, letter, chat, other }

enum FollowUpStatus { open, completed }

class Party {
  const Party({required this.id, required this.name});
  final PartyId id;
  final String name;
}

class FollowUp {
  const FollowUp({required this.dueAt, this.status = FollowUpStatus.open});
  final DateTime dueAt;
  final FollowUpStatus status;
  FollowUp complete() =>
      FollowUp(dueAt: dueAt, status: FollowUpStatus.completed);
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
    String? summary,
    DateTime? createdAt,
    FollowUp? followUp,
  }) => Interaction(
    id: id,
    partyId: partyId,
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

class CreateInteractionCommand {
  const CreateInteractionCommand({
    required this.partyName,
    required this.summary,
    this.followUpDueAt,
    this.timestamp,
    this.method = CommunicationMethod.phone,
    this.contactName,
    this.referenceNumbers = const [],
    this.commitment,
  });
  final String partyName;
  final String summary;
  final DateTime? followUpDueAt;
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
  });
  final Interaction interaction;
  final String summary;
}
