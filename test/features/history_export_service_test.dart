import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/core/date_format.dart';
import 'package:my_little_crm/core/clock.dart';
import 'package:my_little_crm/domain/crm_service.dart';
import 'package:my_little_crm/domain/models.dart';
import 'package:my_little_crm/domain/repositories.dart';
import 'package:my_little_crm/features/export/history_export_service.dart';
import 'package:my_little_crm/features/parties/party_history_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('exports a long Unicode history across multiple PDF pages', () async {
    final service = CrmService(
      parties: MemoryPartyRepository(),
      interactions: MemoryInteractionRepository(),
      clock: FixedClock(DateTime.utc(2026, 11, 11)),
    );
    final party = await service.parties.findOrCreate('Renée — Énergie');
    for (var index = 0; index < 80; index++) {
      await service.interactions.save(
        Interaction(
          id: '$index',
          partyId: party.id,
          summary: 'Révision proposée — numéro $index',
          timestamp: DateTime.utc(2026, 1, 1).add(Duration(days: index)),
          createdAt: DateTime.utc(2026),
        ),
      );
    }
    await service.interactions.save(
      Interaction(
        id: 'long',
        partyId: party.id,
        summary: List.filled(3000, 'Long conversation detail.').join(' '),
        timestamp: DateTime.utc(2026, 11),
        createdAt: DateTime.utc(2026),
      ),
    );
    final document = await HistoryExportService(service).exportPdf(party.id);
    expect(document.bytes.length, greaterThan(10000));
    final json = jsonDecode(
      (await HistoryExportService(service).exportJson(party.id)).content,
    );
    expect(json['interactions'].length, 81);
    expect(json['party']['name'], 'Renée — Énergie');
  });

  test('refuses incomplete PDF text while retaining Unicode in JSON', () async {
    final service = CrmService(
      parties: MemoryPartyRepository(),
      interactions: MemoryInteractionRepository(),
      clock: FixedClock(DateTime.utc(2026, 11, 11)),
    );
    final party = await service.parties.findOrCreate('東京保険');
    await service.interactions.save(
      Interaction(
        id: 'unicode',
        partyId: party.id,
        summary: 'مرحبا from renewal desk 🙂',
        timestamp: DateTime.utc(2026, 11, 11),
        createdAt: DateTime.utc(2026, 11, 11),
      ),
    );
    final exporter = HistoryExportService(service);

    final json = await exporter.exportJson(party.id);

    expect(json.content, contains('東京保険'));
    expect(json.content, contains('مرحبا'));
    expect(json.content, contains('🙂'));
    await expectLater(
      exporter.exportPdf(party.id),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Choose JSON instead'),
        ),
      ),
    );
  });

  test('refuses PDF text with a carriage return', () async {
    final service = CrmService(
      parties: MemoryPartyRepository(),
      interactions: MemoryInteractionRepository(),
      clock: FixedClock(DateTime.utc(2026, 11, 11)),
    );
    final party = await service.parties.findOrCreate('Bright\rSure Insurance');
    final exporter = HistoryExportService(service);

    expect(
      (await exporter.exportJson(party.id)).content,
      contains('Bright\\rSure'),
    );
    await expectLater(exporter.exportPdf(party.id), throwsA(isA<StateError>()));
  });

  test('exports text supported by the bundled Greek glyphs', () async {
    final service = CrmService(
      parties: MemoryPartyRepository(),
      interactions: MemoryInteractionRepository(),
      clock: FixedClock(DateTime.utc(2026, 11, 11)),
    );
    final party = await service.parties.findOrCreate('Καλημέρα');

    final document = await HistoryExportService(service).exportPdf(party.id);

    expect(ascii.decode(document.bytes.take(5).toList()), '%PDF-');
  });

  test('exports supported euro and Vietnamese glyphs', () async {
    final service = CrmService(
      parties: MemoryPartyRepository(),
      interactions: MemoryInteractionRepository(),
      clock: FixedClock(DateTime.utc(2026, 11, 11)),
    );
    final party = await service.parties.findOrCreate('€100 deposit');
    await service.interactions.save(
      Interaction(
        id: 'vietnamese',
        partyId: party.id,
        summary: 'Tiếng Việt: ạ và ế',
        timestamp: DateTime.utc(2026, 11, 11),
        createdAt: DateTime.utc(2026, 11, 11),
      ),
    );

    final document = await HistoryExportService(service).exportPdf(party.id);

    expect(ascii.decode(document.bytes.take(5).toList()), '%PDF-');
  });

  testWidgets('explains how to export unsupported PDF text safely', (
    tester,
  ) async {
    final service = CrmService(
      parties: MemoryPartyRepository(),
      interactions: MemoryInteractionRepository(),
      clock: FixedClock(DateTime.utc(2026, 11, 11)),
    );
    final party = await service.parties.findOrCreate('東京保険');
    await service.interactions.save(
      Interaction(
        id: 'unicode',
        partyId: party.id,
        summary: 'مرحبا',
        timestamp: DateTime.utc(2026, 11, 11),
        createdAt: DateTime.utc(2026, 11, 11),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PartyHistoryScreen(service: service, party: party),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Export history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export PDF'));
    await tester.pumpAndSettle();

    expect(
      find.text(HistoryExportService.unsupportedPdfTextMessage),
      findsOneWidget,
    );
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

  group('localized PDF dates (font coverage)', () {
    final at = DateTime(2026, 11, 17, 14, 5);
    HistoryExportService exporter(String locale) => HistoryExportService(
      CrmService.inMemory(),
      dateFormat: AppDateFormat(
        locale: locale,
        use24HourFormat: true,
        now: DateTime(2026, 11, 15),
      ),
    );

    test('falls back to en_US when the font lacks the locale glyphs', () {
      expect(exporter('ja').pdfDateTime(at), 'Tue, Nov 17, 2026 14:05');
      expect(exporter('zh_CN').pdfDate(at), 'Tue, Nov 17, 2026');
    });

    test('keeps supported locales', () {
      expect(exporter('de_DE').pdfDateTime(at), 'Di., 17. Nov. 2026 14:05');
      expect(exporter('en_AU').pdfDate(at), 'Tue, 17 Nov 2026');
    });

    test('a Japanese-locale history still exports', () async {
      final service = CrmService.inMemory();
      final item = await service.createInteraction(
        CreateInteractionCommand(
          partyName: 'BrightSure',
          summary: 'ASCII only',
          timestamp: at.toUtc(),
          followUpDueAt: DateTime(2026, 11, 20).toUtc(),
        ),
      );
      final pdf = await HistoryExportService(
        service,
        dateFormat: AppDateFormat(
          locale: 'ja',
          use24HourFormat: true,
          now: DateTime(2026, 11, 15),
        ),
      ).exportPdf(item.partyId);
      expect(pdf.bytes, isNotEmpty);
    });
  });
}
