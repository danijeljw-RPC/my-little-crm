import 'dart:io';

import 'package:sqflite/sqflite.dart' as sqlite;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:my_little_crm/app.dart';
import 'package:my_little_crm/core/clock.dart';
import 'package:my_little_crm/data/local/app_database.dart';
import 'package:my_little_crm/data/local/interaction_repository.dart';
import 'package:my_little_crm/data/local/party_repository.dart';
import 'package:my_little_crm/domain/crm_service.dart';
import 'package:my_little_crm/domain/models.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reopened FTS4 index matches reordered partial words', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp('crm-fts4-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/fts4.sqlite';
    final initial = await AppDatabase.open(path: path);
    await initial.close();
    final native = await sqlite.openDatabase(path);
    await native.execute('DROP TABLE interaction_search');
    await native.execute(
      'CREATE VIRTUAL TABLE interaction_search USING fts4(id, summary)',
    );
    await native.close();
    final db = await AppDatabase.open(path: path);
    addTearDown(db.close);
    final service = CrmService(
      parties: LocalPartyRepository(db),
      interactions: LocalInteractionRepository(db),
      clock: FixedClock(DateTime.utc(2026, 11, 11)),
    );
    final record = await service.createInteraction(
      const CreateInteractionCommand(
        partyName: 'Insurance',
        summary: 'Premium payment remains disputed',
      ),
    );
    expect(
      (await service.searchInteractions('disput prem')).single.id,
      record.id,
    );
    final accented = await service.createInteraction(
      const CreateInteractionCommand(
        partyName: 'Énergie',
        summary: 'Billing call',
      ),
    );
    expect(
      (await service.searchInteractions('éNERGIE')).single.id,
      accented.id,
    );
  });

  testWidgets(
    'offline records survive reopening and completed follow-ups remain in history',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'crm-acceptance-',
      );
      final path = '${directory.path}/journey.sqlite';
      var database = await AppDatabase.open(path: path);
      CrmService serviceFor(AppDatabase db) => CrmService(
        parties: LocalPartyRepository(db),
        interactions: LocalInteractionRepository(db),
        clock: FixedClock(DateTime.utc(2026, 11, 11, 10)),
      );
      var service = serviceFor(database);
      final first = await service.createInteraction(
        CreateInteractionCommand(
          partyName: 'BrightSure Insurance',
          summary: 'Premium disputed: BS-841902.',
          followUpDueAt: DateTime.utc(2026, 11, 14),
        ),
      );
      await service.createInteraction(
        const CreateInteractionCommand(
          partyName: 'BrightSure Insurance',
          summary: 'Revised quote promised',
        ),
      );
      expect(await service.searchInteractions('8419'), hasLength(1));
      await tester.pumpWidget(MyLittleCrmApp(service: service));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add interaction'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('party-name')),
        'BrightSure Insurance',
      );
      await tester.enterText(
        find.byKey(const Key('summary')),
        'Received the revised quote',
      );
      await tester.ensureVisible(find.text('Save interaction'));
      await tester.tap(find.text('Save interaction'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Follow-ups'));
      await tester.pumpAndSettle();
      expect(find.text('Premium disputed: BS-841902.'), findsOneWidget);
      await tester.tap(find.byTooltip('Complete follow-up'));
      await tester.pumpAndSettle();
      expect(find.text('Premium disputed: BS-841902.'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await database.close();
      database = await AppDatabase.open(path: path);
      service = serviceFor(database);
      expect(await service.outstandingFollowUps(), isEmpty);
      final history = await service.partyHistory(first.partyId);
      expect(history, hasLength(3));
      expect(
        history.singleWhere((item) => item.id == first.id).followUp!.status,
        FollowUpStatus.completed,
      );
      await tester.pumpWidget(MyLittleCrmApp(service: service));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Parties'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('BrightSure Insurance'));
      await tester.pumpAndSettle();
      expect(find.text('Premium disputed: BS-841902.'), findsOneWidget);
      expect(find.text('Revised quote promised'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await database.close();
      await directory.delete(recursive: true);
    },
  );
}
