import 'package:flutter/material.dart';
import 'package:my_little_crm/features/interactions/interaction_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/app.dart';
import 'package:my_little_crm/core/clock.dart';
import 'package:my_little_crm/domain/crm_service.dart';
import 'package:my_little_crm/domain/models.dart';
import 'package:my_little_crm/domain/repositories.dart';

void main() {
  testWidgets(
    'failed follow-up completion keeps the item available for retry',
    (tester) async {
      final interactions = _FailingSaveRepository();
      final service = CrmService(
        parties: MemoryPartyRepository(),
        interactions: interactions,
        clock: FixedClock(DateTime.utc(2026)),
      );
      await service.createInteraction(
        CreateInteractionCommand(
          partyName: 'BrightSure',
          summary: 'Request quote',
          followUpDueAt: DateTime.utc(2027),
        ),
      );
      interactions.fail = true;
      await tester.pumpWidget(MyLittleCrmApp(service: service));
      await tester.tap(find.text('Follow-ups'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Complete follow-up'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.text('Could not complete follow-up. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Request quote'), findsOneWidget);
      interactions.fail = false;
      await tester.tap(find.byTooltip('Complete follow-up'));
      await tester.pumpAndSettle();
      expect(find.text('No outstanding follow-ups'), findsOneWidget);
    },
  );
  testWidgets('home records open editable history and refresh on return', (
    tester,
  ) async {
    final service = CrmService(
      parties: MemoryPartyRepository(),
      interactions: MemoryInteractionRepository(),
      clock: FixedClock(DateTime.utc(2026)),
    );
    await service.createInteraction(
      const CreateInteractionCommand(
        partyName: 'BrightSure',
        summary: 'Original call',
      ),
    );
    await tester.pumpWidget(MyLittleCrmApp(service: service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Original call'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Export history'), findsOneWidget);
    await tester.tap(find.text('Original call'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('summary')), 'Edited call');
    await tester.ensureVisible(find.text('Save interaction'));
    await tester.tap(find.text('Save interaction'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Edited call'), findsOneWidget);
    expect(find.text('Original call'), findsNothing);
  });

  testWidgets('suggests existing parties while recording a conversation', (
    tester,
  ) async {
    final service = CrmService(
      parties: MemoryPartyRepository(),
      interactions: MemoryInteractionRepository(),
      clock: FixedClock(DateTime.utc(2026)),
    );
    await service.parties.findOrCreate('BrightSure Insurance');
    await tester.pumpWidget(MyLittleCrmApp(service: service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add interaction'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('party-name')), 'bright');
    await tester.pumpAndSettle();
    await tester.tap(find.text('BrightSure Insurance'));
    await tester.enterText(find.byKey(const Key('summary')), 'New call');
    await tester.ensureVisible(find.text('Save interaction'));
    await tester.tap(find.text('Save interaction'));
    await tester.pumpAndSettle();
    expect((await service.parties.list()).length, 1);
    expect(find.text('BrightSure Insurance'), findsOneWidget);
  });

  testWidgets(
    'editing retains the original party ID without creating a name lookup party',
    (tester) async {
      final parties = MemoryPartyRepository();
      final interactions = MemoryInteractionRepository();
      final service = CrmService(
        parties: parties,
        interactions: interactions,
        clock: FixedClock(DateTime.utc(2026)),
      );
      final item = await service.createInteraction(
        const CreateInteractionCommand(
          partyName: 'Énergie',
          summary: 'Original call',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => editInteraction(
                  context,
                  service,
                  existing: item,
                  partyName: 'énergie',
                ),
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('summary')), 'Edited call');
      await tester.ensureVisible(find.text('Save interaction'));
      await tester.tap(find.text('Save interaction'));
      await tester.pumpAndSettle();
      expect((await parties.list()).length, 1);
      expect((await interactions.get(item.id))!.partyId, item.partyId);
      expect((await interactions.get(item.id))!.summary, 'Edited call');
    },
  );

  testWidgets('rescheduling a completed follow-up reopens it', (tester) async {
    final service = CrmService(
      parties: MemoryPartyRepository(),
      interactions: MemoryInteractionRepository(),
      clock: FixedClock(DateTime.utc(2026, 11, 11, 10)),
    );
    final item = await service.createInteraction(
      CreateInteractionCommand(
        partyName: 'BrightSure Insurance',
        summary: 'Request an updated quote',
        followUpDueAt: DateTime.utc(2026, 11, 14),
      ),
    );
    await service.completeFollowUp(item.id);
    final completed = (await service.getInteraction(item.id))!;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => editInteraction(
                context,
                service,
                existing: completed,
                partyName: 'BrightSure Insurance',
              ),
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove follow-up'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add follow-up date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save interaction'));
    await tester.tap(find.text('Save interaction'));
    await tester.pumpAndSettle();

    expect(
      (await service.getInteraction(item.id))!.followUp!.status,
      FollowUpStatus.open,
    );
    expect(await service.outstandingFollowUps(), hasLength(1));
  });

  testWidgets('editing details keeps a completed follow-up completed', (
    tester,
  ) async {
    final service = CrmService(
      parties: MemoryPartyRepository(),
      interactions: MemoryInteractionRepository(),
      clock: FixedClock(DateTime.utc(2026, 11, 11, 10)),
    );
    final item = await service.createInteraction(
      CreateInteractionCommand(
        partyName: 'BrightSure Insurance',
        summary: 'Request an updated quote',
        followUpDueAt: DateTime.utc(2026, 11, 14),
      ),
    );
    await service.completeFollowUp(item.id);
    final completed = (await service.getInteraction(item.id))!;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => editInteraction(
                context,
                service,
                existing: completed,
                partyName: 'BrightSure Insurance',
              ),
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('summary')), 'Quote received');
    await tester.ensureVisible(find.text('Save interaction'));
    await tester.tap(find.text('Save interaction'));
    await tester.pumpAndSettle();

    final saved = (await service.getInteraction(item.id))!;
    expect(saved.summary, 'Quote received');
    expect(saved.followUp!.status, FollowUpStatus.completed);
    expect(await service.outstandingFollowUps(), isEmpty);
  });

  testWidgets('records an interaction and retains it in the party timeline', (
    tester,
  ) async {
    final service = CrmService(
      parties: MemoryPartyRepository(),
      interactions: MemoryInteractionRepository(),
      clock: FixedClock(DateTime.utc(2026, 11, 11, 10)),
    );

    await tester.pumpWidget(MyLittleCrmApp(service: service));
    await tester.tap(find.text('Add interaction'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('party-name')),
      'BrightSure Insurance',
    );
    await tester.enterText(
      find.byKey(const Key('summary')),
      'Revised quote promised',
    );
    await tester.tap(find.text('Save interaction'));
    await tester.pumpAndSettle();

    expect(find.text('BrightSure Insurance'), findsOneWidget);
    expect(find.text('Revised quote promised'), findsOneWidget);
  });

  testWidgets(
    'shows open follow-ups and removes a completed item from that list',
    (tester) async {
      final clock = FixedClock(DateTime.utc(2026, 11, 11, 10));
      final service = CrmService(
        parties: MemoryPartyRepository(),
        interactions: MemoryInteractionRepository(),
        clock: clock,
      );
      await service.createInteraction(
        CreateInteractionCommand(
          partyName: 'BrightSure Insurance',
          summary: 'Revised quote promised',
          followUpDueAt: DateTime.utc(2026, 11, 14),
        ),
      );

      await tester.pumpWidget(MyLittleCrmApp(service: service));
      await tester.tap(find.text('Follow-ups'));
      await tester.pumpAndSettle();

      expect(find.text('BrightSure Insurance'), findsOneWidget);
      expect(find.text('Revised quote promised'), findsOneWidget);
      await tester.tap(find.byTooltip('Complete follow-up'));
      await tester.pumpAndSettle();
      expect(find.text('Revised quote promised'), findsNothing);
    },
  );
}

class _FailingSaveRepository extends MemoryInteractionRepository {
  bool fail = false;
  @override
  Future<Interaction> save(Interaction value) async {
    if (fail) throw StateError('Disk unavailable');
    return super.save(value);
  }
}
