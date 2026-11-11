import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/core/clock.dart';
import 'package:my_little_crm/domain/crm_service.dart';
import 'package:my_little_crm/domain/models.dart';
import 'package:my_little_crm/domain/repositories.dart';
import 'package:my_little_crm/features/export/history_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('exports a long Unicode history across multiple PDF pages', () async {
    final service = CrmService(parties: MemoryPartyRepository(), interactions: MemoryInteractionRepository(), clock: FixedClock(DateTime.utc(2026, 11, 11)));
    final party = await service.parties.findOrCreate('Renée — Énergie');
    for (var index = 0; index < 80; index++) {
      await service.interactions.save(Interaction(id: '$index', partyId: party.id, summary: 'Révision proposée — numéro $index', timestamp: DateTime.utc(2026, 1, 1).add(Duration(days: index)), createdAt: DateTime.utc(2026)));
    }
    await service.interactions.save(Interaction(id: 'long', partyId: party.id, summary: List.filled(3000, 'Long conversation detail.').join(' '), timestamp: DateTime.utc(2026, 11), createdAt: DateTime.utc(2026)));
    final document = await HistoryExportService(service).exportPdf(party.id);
    expect(document.bytes.length, greaterThan(10000));
    final json = jsonDecode((await HistoryExportService(service).exportJson(party.id)).content);
    expect(json['interactions'].length, 81);
    expect(json['party']['name'], 'Renée — Énergie');
  });
  test(
    'exports complete chronological JSON and a readable PDF document',
    () async {
      final service = CrmService(
        parties: MemoryPartyRepository(),
        interactions: MemoryInteractionRepository(),
        clock: FixedClock(DateTime.utc(2026, 11, 11)),
      );
      final party = await service.parties.findOrCreate('BrightSure Insurance');
      await service.interactions.save(
        Interaction(
          id: 'later',
          partyId: party.id,
          summary: 'Revised quote promised',
          timestamp: DateTime.utc(2026, 11, 12),
          createdAt: DateTime.utc(2026, 11, 12),
          referenceNumbers: ['BS-841902'],
          contactName: 'Sam',
          commitment: 'Send quote',
          followUp: FollowUp(dueAt: DateTime.utc(2026, 11, 15)),
        ),
      );
      await service.interactions.save(
        Interaction(
          id: 'first',
          partyId: party.id,
          summary: 'Initial discussion',
          timestamp: DateTime.utc(2026, 11, 10),
          createdAt: DateTime.utc(2026, 11, 10),
        ),
      );
      final exporter = HistoryExportService(service);
      final json = jsonDecode(
        (await exporter.exportJson(party.id)).content,
      ) as Map<String, dynamic>;
      expect(json['schemaVersion'], 1);
      expect(json['party']['name'], 'BrightSure Insurance');
      expect(json['interactions'][0]['id'], 'first');
      expect(json['interactions'][1]['referenceNumbers'], ['BS-841902']);
      expect(json['interactions'][1]['followUp']['status'], 'open');
      final pdf = await exporter.exportPdf(party.id);
      expect(ascii.decode(pdf.bytes.take(5).toList()), '%PDF-');
      expect(pdf.bytes.length, greaterThan(1000));
    },
  );
}
