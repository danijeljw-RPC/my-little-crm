// The browser demo (#30): seeded sample data on a throwaway database, the
// demo banner, and an in-memory-only web database.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/app.dart';
import 'package:my_little_crm/core/clock.dart';
import 'package:my_little_crm/data/local/app_database.dart';
import 'package:my_little_crm/data/local/interaction_repository.dart';
import 'package:my_little_crm/data/local/party_repository.dart';
import 'package:my_little_crm/demo/demo_data.dart';
import 'package:my_little_crm/demo/demo_mode.dart';
import 'package:my_little_crm/domain/crm_service.dart';
import 'package:my_little_crm/domain/models.dart';

// A morning, so the "due today at 16:30" follow-up is still due today.
final _now = DateTime(2026, 11, 16, 9).toUtc();

Future<CrmService> _demoService() async {
  final db = await AppDatabase.inMemory();
  addTearDown(db.close);
  final service = CrmService(
    parties: LocalPartyRepository(db),
    interactions: LocalInteractionRepository(db),
    clock: FixedClock(_now),
  );
  await seedDemoLedger(service);
  return service;
}

void main() {
  test('the flag is off unless --dart-define=DEMO_MODE=true', () {
    expect(demoModeFlag, isFalse);
    expect(isDemoMode, isFalse); // Tests run on the VM, not the web.
  });

  group('sample data', () {
    test('seeds parties, interactions and every follow-up state', () async {
      final service = await _demoService();
      final parties = await service.parties.list();
      final interactions = await service.interactions.all();
      expect(parties, hasLength(8));
      expect(interactions.length, greaterThanOrEqualTo(15));
      expect(
        CommunicationMethod.values.where(
          (m) => interactions.any((i) => i.method == m),
        ),
        hasLength(CommunicationMethod.values.length),
      );
      expect(interactions.any((i) => i.referenceNumbers.isNotEmpty), isTrue);
      expect(interactions.any((i) => i.commitment != null), isTrue);

      final open = await service.outstandingFollowUps();
      final urgencies = open.map((i) => i.followUp!.urgency(_now)).toSet();
      expect(urgencies, FollowUpUrgency.values.toSet());
      expect(await service.overdueFollowUpCount(), 2);
      expect(
        interactions.where(
          (i) => i.followUp?.status == FollowUpStatus.completed,
        ),
        isNotEmpty,
      );
      // No interaction is in the future: the ledger records what happened.
      expect(interactions.every((i) => !i.timestamp.isAfter(_now)), isTrue);
    });

    test('is searchable through the real SQLite full-text index', () async {
      final service = await _demoService();
      final hits = await service.searchInteractions('CLM-2025-66410');
      expect(hits, hasLength(2));
      expect((await service.searchInteractions('plumber')), isNotEmpty);
    });

    test('can be created, edited and deleted like real records', () async {
      final service = await _demoService();
      final created = await service.createInteraction(
        const CreateInteractionCommand(
          partyName: 'Harbourside Bank',
          summary: 'Asked about the new savings account',
        ),
      );
      final edited = await service.updateInteraction(
        UpdateInteractionCommand(
          interaction: created,
          summary: 'Opened the new savings account',
        ),
      );
      expect(
        (await service.getInteraction(created.id))!.summary,
        edited.summary,
      );
      await service.deleteInteraction(created.id);
      expect(await service.getInteraction(created.id), isNull);

      final party = (await service.parties.list()).first;
      await service.deleteParty(party.id);
      expect(await service.parties.get(party.id), isNull);
    });

    test('each launch starts from a fresh copy', () async {
      final first = await _demoService();
      await first.deleteParty((await first.parties.list()).first.id);
      final second = await _demoService();
      expect(await second.parties.list(), hasLength(8));
    });
  });

  group('banner', () {
    testWidgets('is shown in demo mode', (tester) async {
      await tester.pumpWidget(const MyLittleCrmApp(demo: true));
      await tester.pumpAndSettle();
      expect(find.text(demoBannerText), findsOneWidget);
      expect(demoBannerText, startsWith('Demo Mode:'));
      expect(find.text('My Little CRM'), findsOneWidget);
    });

    testWidgets('is not shown in the real app', (tester) async {
      await tester.pumpWidget(const MyLittleCrmApp());
      await tester.pumpAndSettle();
      expect(find.text(demoBannerText), findsNothing);
    });

    testWidgets('stays visible on a phone-sized screen', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MyLittleCrmApp(demo: true));
      await tester.pumpAndSettle();
      expect(find.text(demoBannerText), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('web database', () {
    final source = File('lib/data/local/database_opener_web.dart')
        .readAsStringSync();

    test('keeps everything in memory, in this page only', () {
      // inMemory: nothing in IndexedDB; noWebWorker: a shared worker would
      // outlive a refresh while another tab is open.
      expect(source, contains('inMemory: true'));
      expect(source, contains('noWebWorker: true'));
      for (final storage in ['indexedDbName', 'localStorage', 'OPFS']) {
        expect(source, isNot(contains('$storage:')), reason: storage);
      }
    });

    test('main never opens the real ledger in demo mode', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(
        main,
        contains(
          'isDemoMode\n      ? await AppDatabase.inMemory()\n'
          '      : await AppDatabase.open()',
        ),
      );
    });
  });
}
