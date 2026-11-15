import 'dart:convert';

import 'models.dart';

/// Every party and interaction, as written by "Export everything" (#37).
///
/// The JSON format is versioned by [formatVersion] and is **not encrypted**.
class LedgerSnapshot {
  const LedgerSnapshot({
    required this.generatedAt,
    required this.parties,
    required this.interactions,
  });

  static const format = 'my-little-crm-ledger';
  static const formatVersion = 1;

  final DateTime generatedAt;
  final List<Party> parties;
  final List<Interaction> interactions;

  String toJson() => const JsonEncoder.withIndent('  ').convert({
    'format': format,
    'formatVersion': formatVersion,
    'encrypted': false,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'parties': [
      for (final p in parties) {'id': p.id, 'name': p.name},
    ],
    'interactions': [for (final i in interactions) interactionToJson(i)],
  });

  static LedgerSnapshot fromJson(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('This file is not valid JSON.');
    }
    if (decoded is! Map<String, Object?> || decoded['format'] != format) {
      throw const FormatException(
        'This file is not a My Little CRM "Export everything" file.',
      );
    }
    final version = decoded['formatVersion'];
    if (version is! int || version > formatVersion) {
      throw const FormatException(
        'This export was made by a newer version of My Little CRM.',
      );
    }
    try {
      return LedgerSnapshot(
        generatedAt: DateTime.parse(decoded['generatedAt']! as String).toUtc(),
        parties: [
          for (final p
              in (decoded['parties']! as List<Object?>)
                  .cast<Map<String, Object?>>())
            Party(id: p['id']! as String, name: p['name']! as String),
        ],
        interactions: [
          for (final i in decoded['interactions']! as List<Object?>)
            interactionFromJson(i! as Map<String, Object?>),
        ],
      );
    } on Object catch (error) {
      if (error is FormatException) rethrow;
      throw const FormatException('This export file is incomplete or damaged.');
    }
  }

  static Map<String, Object?> interactionToJson(Interaction i) => {
    'id': i.id,
    'partyId': i.partyId,
    'timestamp': i.timestamp.toUtc().toIso8601String(),
    'createdAt': i.createdAt.toUtc().toIso8601String(),
    'method': i.method.name,
    'contactName': i.contactName,
    'summary': i.summary,
    'referenceNumbers': i.referenceNumbers,
    'commitment': i.commitment,
    'followUp': i.followUp == null
        ? null
        : {
            'dueAt': i.followUp!.dueAt.toUtc().toIso8601String(),
            'hasTime': i.followUp!.hasTime,
            'status': i.followUp!.status.name,
          },
  };

  static Interaction interactionFromJson(Map<String, Object?> json) {
    final followUp = json['followUp'] as Map<String, Object?>?;
    return Interaction(
      id: json['id']! as String,
      partyId: json['partyId']! as String,
      timestamp: DateTime.parse(json['timestamp']! as String).toUtc(),
      createdAt: DateTime.parse(json['createdAt']! as String).toUtc(),
      method: CommunicationMethod.values.byName(json['method']! as String),
      contactName: json['contactName'] as String?,
      summary: json['summary']! as String,
      referenceNumbers: [
        for (final r in json['referenceNumbers']! as List<Object?>)
          r! as String,
      ],
      commitment: json['commitment'] as String?,
      followUp: followUp == null
          ? null
          : FollowUp(
              dueAt: DateTime.parse(followUp['dueAt']! as String).toUtc(),
              hasTime: followUp['hasTime'] as bool? ?? false,
              status: FollowUpStatus.values.byName(
                followUp['status']! as String,
              ),
            ),
    );
  }
}
