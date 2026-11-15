import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/app.dart';
import 'package:my_little_crm/core/clock.dart';
import 'package:my_little_crm/domain/crm_service.dart';
import 'package:my_little_crm/domain/models.dart';
import 'package:my_little_crm/domain/repositories.dart';
import 'package:my_little_crm/features/export/ledger_transfer.dart';
import 'package:my_little_crm/features/interactions/interaction_editor.dart';

const _phone = Size(400, 800);
const _desktop = Size(1280, 800);

void _size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

Future<CrmService> _service() async {
  final service = CrmService.inMemory(
    clock: FixedClock(DateTime.utc(2026, 11, 15, 12)),
  );
  for (final (party, summary, day) in [
    ('BrightSure', 'Quote call', 10),
    ('BrightSure', 'Renewal letter', 11),
    ('Brightsure Ins.', 'Typo record', 12),
  ]) {
    await service.createInteraction(
      CreateInteractionCommand(
        partyName: party,
        summary: summary,
        timestamp: DateTime.utc(2026, 11, day),
      ),
    );
  }
  return service;
}

Future<void> _pump(WidgetTester tester, CrmService service, Size size) async {
  _size(tester, size);
  await tester.pumpWidget(MyLittleCrmApp(service: service));
  await tester.pumpAndSettle();
}

Future<void> _tapShown(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('responsive layout (#31)', () {
    testWidgets('compact: bottom bar, pushed history, editor bottom sheet', (
      tester,
    ) async {
      await _pump(tester, await _service(), _phone);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);

      await tester.tap(find.text('Add interaction'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      await tester.tapAt(const Offset(200, 20)); // dismiss
      await tester.pumpAndSettle();

      await tester.tap(find.text('Quote call'));
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.text('BrightSure'), findsOneWidget); // history app bar
    });

    testWidgets('expanded: rail, side-by-side detail and editor dialog', (
      tester,
    ) async {
      await _pump(tester, await _service(), _desktop);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(
        find.text('Select an interaction to see it in its party history'),
        findsOneWidget,
      );

      await tester.tap(find.text('Quote call'));
      await tester.pumpAndSettle();
      // The list stays visible next to the party history.
      expect(find.byType(BackButton), findsNothing);
      expect(find.text('Quote call'), findsNWidgets(2));
      expect(find.text('Renewal letter'), findsNWidgets(2));
      final list = tester.getCenter(find.text('Quote call').first);
      final detail = tester.getCenter(find.text('Quote call').last);
      expect(detail.dx, greaterThan(list.dx + 300));

      await tester.tap(find.text('Add interaction'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        tester.getSize(find.byType(InteractionEditor)).width,
        lessThanOrEqualTo(560),
      );
    });

    testWidgets('expanded parties: list next to history', (tester) async {
      await _pump(tester, await _service(), _desktop);
      await tester.tap(find.text('Parties'));
      await tester.pumpAndSettle();
      expect(find.text('Select a party to see its history'), findsOneWidget);
      await tester.tap(find.text('BrightSure'));
      await tester.pumpAndSettle();
      expect(find.text('BrightSure'), findsNWidgets(2)); // list + app bar
      expect(find.text('Quote call'), findsOneWidget);
      expect(find.text('Brightsure Ins.'), findsOneWidget); // still listed
    });
  });

  group('delete (#36)', () {
    testWidgets('confirms, deletes, and Undo restores the interaction', (
      tester,
    ) async {
      final service = await _service();
      await _pump(tester, service, _phone);
      await tester.tap(find.text('Quote call'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quote call'));
      await tester.pumpAndSettle();
      await _tapShown(tester, find.text('Delete interaction'));
      expect(find.text('Delete this interaction?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Edit interaction'), findsOneWidget);

      await _tapShown(tester, find.text('Delete interaction'));
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Interaction deleted'), findsOneWidget);
      expect(find.text('Quote call'), findsNothing);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Quote call'), findsOneWidget);
      expect(await service.searchInteractions('Quote'), hasLength(1));
    });

    testWidgets('deleting a party states how many interactions go with it', (
      tester,
    ) async {
      final service = await _service();
      await _pump(tester, service, _phone);
      await tester.tap(find.text('Parties'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('BrightSure'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Party actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete party'));
      await tester.pumpAndSettle();
      expect(
        find.text('This also deletes 2 interactions. This cannot be undone.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Delete party and 2'));
      await tester.pumpAndSettle();
      // Back on the party list, which no longer has the party.
      expect(find.byType(BackButton), findsNothing);
      expect(find.text('BrightSure'), findsNothing);
      expect(find.text('Brightsure Ins.'), findsOneWidget);
      expect(await service.searchInteractions('Quote'), isEmpty);
    });
  });

  group('party editor (#32)', () {
    testWidgets('rename, and a clashing rename offers merge', (tester) async {
      final service = await _service();
      await _pump(tester, service, _phone);
      await tester.tap(find.text('Parties'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Brightsure Ins.'));
      await tester.pumpAndSettle();

      Future<void> rename(String name) async {
        await tester.tap(find.byTooltip('Party actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rename'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('rename-party')), name);
        await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
        await tester.pumpAndSettle();
      }

      await rename('Brightsure Insurance');
      expect(find.text('Brightsure Insurance'), findsOneWidget);

      await rename('brightsure');
      expect(find.text('"BrightSure" already exists'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
      await tester.pumpAndSettle();
      // Now showing the merged party with all three records.
      expect(find.text('BrightSure'), findsOneWidget);
      for (final summary in ['Quote call', 'Renewal letter', 'Typo record']) {
        expect(find.text(summary), findsOneWidget);
      }
      expect(await service.parties.list(), hasLength(1));
    });

    testWidgets('merge picks a target and confirms the move', (tester) async {
      final service = await _service();
      await _pump(tester, service, _phone);
      await tester.tap(find.text('Parties'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Brightsure Ins.'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Party actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Merge into another party'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('BrightSure'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('1 interaction will move'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
      await tester.pumpAndSettle();
      expect(find.text('Typo record'), findsOneWidget);
      expect(find.text('Quote call'), findsOneWidget);
      expect(await service.parties.list(), hasLength(1));
    });
  });

  testWidgets('moving an interaction refreshes both histories (#33)', (
    tester,
  ) async {
    final service = await _service();
    await _pump(tester, service, _desktop);
    await tester.tap(find.text('Parties'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brightsure Ins.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Typo record').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Change this to move the interaction to another party'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('party-name')), 'BrightSure');
    await _tapShown(tester, find.text('Save interaction'));
    expect(find.text('No interactions with this party'), findsOneWidget);

    await tester.tap(find.text('BrightSure'));
    await tester.pumpAndSettle();
    expect(find.text('Typo record'), findsOneWidget);
  });

  testWidgets('home list loads pages lazily, never the whole ledger (#39)', (
    tester,
  ) async {
    final interactions = _CountingInteractions();
    final parties = MemoryPartyRepository(interactions);
    interactions.parties = parties;
    final service = CrmService(
      parties: parties,
      interactions: interactions,
      clock: FixedClock(DateTime.utc(2026)),
    );
    for (var i = 0; i < 120; i++) {
      await service.createInteraction(
        CreateInteractionCommand(
          partyName: 'Party ${i % 7}',
          summary: 'Note ${i.toString().padLeft(3, '0')}',
          timestamp: DateTime.utc(2026).add(Duration(hours: i)),
        ),
      );
    }
    await _pump(tester, service, _phone);
    expect(interactions.calls, ['recent(50, first)']);
    expect(find.text('Note 119'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Note 000'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(interactions.calls, [
      'recent(50, first)',
      'recent(50, after)',
      'recent(50, after)',
    ]);
    expect(interactions.forPartyCalls, 0);

    // A change reloads only what is already shown, in one query.
    interactions.calls.clear();
    await service.createInteraction(
      const CreateInteractionCommand(partyName: 'New', summary: 'Latest'),
    );
    await tester.pumpAndSettle();
    expect(interactions.calls.first, 'recent(120, first)');
    expect(interactions.forPartyCalls, 0);
  });

  group('export everything (#37)', () {
    testWidgets('warns that the file is not encrypted', (tester) async {
      await _pump(tester, await _service(), _phone);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      expect(find.text('Not encrypted'), findsOneWidget);
      await tester.tap(find.text('Export everything (JSON)'));
      await tester.pumpAndSettle();
      expect(find.text(LedgerTransfer.notEncryptedWarning), findsOneWidget);
      expect(find.text('Export unencrypted file'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Export everything?'), findsNothing);
    });

    test('the file holds every party and interaction', () async {
      final service = await _service();
      final file = await LedgerTransfer(service).build();
      expect(file.parties, 2);
      expect(file.interactions, 3);
      expect(file.name, 'my-little-crm-export-2026-11-15.json');
    });
  });
}

class _CountingInteractions extends MemoryInteractionRepository {
  final calls = <String>[];
  var forPartyCalls = 0;
  @override
  Future<List<InteractionEntry>> recent({int limit = 50, RecentCursor? after}) {
    calls.add('recent($limit, ${after == null ? 'first' : 'after'})');
    return super.recent(limit: limit, after: after);
  }

  @override
  Future<List<Interaction>> forParty(PartyId partyId) {
    forPartyCalls++;
    return super.forParty(partyId);
  }
}
