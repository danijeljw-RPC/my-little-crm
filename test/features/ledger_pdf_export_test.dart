// Whole-ledger PDF export (#52).
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/core/clock.dart';
import 'package:my_little_crm/domain/crm_service.dart';
import 'package:my_little_crm/domain/models.dart';
import 'package:my_little_crm/features/export/history_export_service.dart';

Future<CrmService> _ledger({int parties = 3, int perParty = 4}) async {
  final service = CrmService.inMemory(
    clock: FixedClock(DateTime.utc(2026, 11, 16)),
  );
  // Created out of name order, so the report has to sort them.
  for (final name in [
    'Zeta Insurance',
    'acme bank',
    'Mira Energy',
  ].take(parties)) {
    final party = await service.parties.findOrCreate(name);
    for (var i = perParty - 1; i >= 0; i--) {
      await service.interactions.save(
        Interaction(
          id: '${party.id}-$i',
          partyId: party.id,
          summary: '$name note $i',
          timestamp: DateTime.utc(2026, 1, 1 + i),
          createdAt: DateTime.utc(2026),
          contactName: i.isEven ? 'Contact $i' : null,
          referenceNumbers: ['REF-$name-$i'],
          commitment: i == 0 ? 'Call back $name' : null,
          followUp: i == 1 ? FollowUp(dueAt: DateTime.utc(2026, 2, 1)) : null,
        ),
      );
    }
  }
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'lists every party by name with its full chronological history',
    () async {
      final service = await _ledger();
      await service.parties.findOrCreate('Empty Co');
      final exporter = HistoryExportService(service);
      final snapshot = await service.snapshot();

      final sections = exporter.ledgerSections(
        snapshot.parties,
        snapshot.interactions,
      );

      expect(sections.map((s) => s.name), [
        'acme bank',
        'Empty Co',
        'Mira Energy',
        'Zeta Insurance',
      ]);
      final empty = sections[1];
      expect(empty.entries, isEmpty);
      final text = sections.expand((s) => s.text).join('\n');
      for (final interaction in snapshot.interactions) {
        expect(text, contains(interaction.summary));
        expect(text, contains('Record: ${interaction.id}'));
        for (final reference in interaction.referenceNumbers) {
          expect(text, contains(reference));
        }
      }
      expect(text, contains('Commitment: Call back Mira Energy'));
      expect(text, contains('Contact: Contact 2'));
      expect(text, contains('Follow-up: '));
      // Oldest first within a party.
      expect(sections.first.entries.map((e) => e.summary), [
        'acme bank note 0',
        'acme bank note 1',
        'acme bank note 2',
        'acme bank note 3',
      ]);
    },
  );

  test(
    'writes a PDF with a contents page and one run of pages per party',
    () async {
      final service = await _ledger();
      await service.parties.findOrCreate('Empty Co');

      final document = await HistoryExportService(service).exportLedgerPdf();

      expect(document.name, 'my-little-crm-report-2026-11-16.pdf');
      expect(ascii.decode(document.bytes.take(5).toList()), '%PDF-');
      final pages = _pageCount(
        await HistoryExportService.renderPdf(
          font: await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
          sections: HistoryExportService(service).ledgerSections(
            (await service.snapshot()).parties,
            (await service.snapshot()).interactions,
          ),
          generatedAt: '2026-11-16T00:00:00.000Z',
          contents: true,
        ),
      );
      // Contents, then each of the four parties starts on its own page.
      expect(pages, 5);
    },
  );

  test('the single-party PDF keeps its own layout without contents', () async {
    final service = await _ledger(parties: 1);
    final party = (await service.parties.list()).single;
    final section = HistoryExportService(service)
        .partySection(party, await service.partyHistory(party.id));

    final bytes = await HistoryExportService.renderPdf(
      font: await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
      sections: [section],
      generatedAt: '2026-11-16T00:00:00.000Z',
      contents: false,
    );

    expect(_pageCount(bytes), 1);
  });

  test('refuses unsupported glyphs and names the affected party', () async {
    final service = await _ledger();
    final party = await service.parties.findOrCreate('Tokyo Desk');
    await service.interactions.save(
      Interaction(
        id: 'jp',
        partyId: party.id,
        summary: '東京で更新',
        timestamp: DateTime.utc(2026, 3),
        createdAt: DateTime.utc(2026, 3),
      ),
    );

    await expectLater(
      HistoryExportService(service).exportLedgerPdf(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('Choose JSON instead'),
            contains('Affected party: "Tokyo Desk"'),
          ),
        ),
      ),
    );
  });

  test('names at most three affected parties', () async {
    final service = CrmService.inMemory(
      clock: FixedClock(DateTime.utc(2026, 11, 16)),
    );
    for (final name in ['A 東', 'B 東', 'C 東', 'D 東', 'E 東']) {
      await service.parties.findOrCreate(name);
    }

    await expectLater(
      HistoryExportService(service).exportLedgerPdf(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Affected parties: "A 東", "B 東", "C 東" and 2 more.'),
        ),
      ),
    );
  });

  test(
    'stops with a clear error instead of truncating at the page cap',
    () async {
      final service = await _ledger(perParty: 60);
      final snapshot = await service.snapshot();
      final sections = HistoryExportService(service)
          .ledgerSections(snapshot.parties, snapshot.interactions);

      await expectLater(
        HistoryExportService.renderPdf(
          font: await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
          sections: sections,
          generatedAt: '2026-11-16T00:00:00.000Z',
          contents: true,
          maxPages: 2,
        ),
        throwsA(
          isA<PdfPageLimitException>()
              .having((e) => e.partyName, 'partyName', 'acme bank')
              .having(
                (e) => e.message,
                'message',
                contains('no file was saved'),
              ),
        ),
      );
    },
  );

  test('a large ledger is generated within the agreed time', () async {
    // 100 parties x 50 interactions = 5,000 interactions. The 50,000
    // interaction measurement lives in tool/benchmark/ledger_benchmark_test.dart.
    final service = CrmService.inMemory(
      clock: FixedClock(DateTime.utc(2026, 11, 16)),
    );
    final items = <Interaction>[];
    for (var p = 0; p < 100; p++) {
      final party = await service.parties.findOrCreate('Party $p');
      for (var i = 0; i < 50; i++) {
        items.add(
          Interaction(
            id: 'p$p-i$i',
            partyId: party.id,
            summary: 'Call $i about the renewal and next steps',
            timestamp: DateTime.utc(2025).add(Duration(hours: p * 50 + i)),
            createdAt: DateTime.utc(2025),
            referenceNumbers: i.isEven ? ['CASE-$p-$i'] : const [],
          ),
        );
      }
    }
    await service.interactions.saveAll(items);

    final watch = Stopwatch()..start();
    final document = await HistoryExportService(service).exportLedgerPdf();
    watch.stop();

    expect(ascii.decode(document.bytes.take(5).toList()), '%PDF-');
    expect(watch.elapsed, lessThan(const Duration(seconds: 60)));
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// Pages in an uncompressed-enough PDF: count page objects, not the tree.
int _pageCount(Uint8List bytes) =>
    RegExp(r'/Type\s*/Page(?![s\w])').allMatches(latin1.decode(bytes)).length;
