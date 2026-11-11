import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/app.dart';
import 'package:my_little_crm/core/clock.dart';
import 'package:my_little_crm/domain/crm_service.dart';
import 'package:my_little_crm/domain/models.dart';
import 'package:my_little_crm/domain/repositories.dart';

void main() {
  testWidgets('search failures are recoverable on the next query', (
    tester,
  ) async {
    final interactions = _FailingSearchRepository();
    final service = CrmService(
      parties: MemoryPartyRepository(),
      interactions: interactions,
      clock: FixedClock(DateTime.utc(2026)),
    );
    await service.createInteraction(
      const CreateInteractionCommand(
        partyName: 'BrightSure',
        summary: 'Refund received',
      ),
    );
    await tester.pumpWidget(MyLittleCrmApp(service: service));
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'refund');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Could not search. Please try again.'), findsOneWidget);
    interactions.fail = false;
    await tester.enterText(find.byType(TextField), 'received');
    await tester.pumpAndSettle();
    expect(find.text('Refund received'), findsOneWidget);
    expect(find.text('Could not search. Please try again.'), findsNothing);
  });
  testWidgets('refreshes preserved search after adding a matching record', (
    tester,
  ) async {
    final service = CrmService(
      parties: MemoryPartyRepository(),
      interactions: MemoryInteractionRepository(),
      clock: FixedClock(DateTime.utc(2026, 11, 11)),
    );
    await tester.pumpWidget(MyLittleCrmApp(service: service));
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'refund');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add interaction'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('party-name')), 'BrightSure');
    await tester.enterText(find.byKey(const Key('summary')), 'Refund promised');
    await tester.ensureVisible(find.text('Save interaction'));
    await tester.tap(find.text('Save interaction'));
    await tester.pumpAndSettle();
    expect(find.text('Refund promised'), findsOneWidget);
    expect(find.text('refund'), findsOneWidget);
  });
  testWidgets('finds an interaction from a partial note search', (
    tester,
  ) async {
    final service = CrmService(
      parties: MemoryPartyRepository(),
      interactions: MemoryInteractionRepository(),
      clock: FixedClock(DateTime.utc(2026, 11, 11)),
    );
    await service.createInteraction(
      const CreateInteractionCommand(
        partyName: 'BrightSure Insurance',
        summary: 'Premium disputed after renewal',
      ),
    );
    await tester.pumpWidget(MyLittleCrmApp(service: service));
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'premium disputed');
    await tester.pumpAndSettle();
    expect(find.text('BrightSure Insurance'), findsOneWidget);
    expect(find.text('Premium disputed after renewal'), findsOneWidget);
  });
  testWidgets('tapping a search result opens that interaction', (tester) async {
    final service = CrmService(
      parties: MemoryPartyRepository(),
      interactions: MemoryInteractionRepository(),
      clock: FixedClock(DateTime.utc(2026, 11, 11)),
    );
    await service.createInteraction(
      const CreateInteractionCommand(
        partyName: 'BrightSure',
        summary: 'Premium disputed fff',
      ),
    );
    await service.createInteraction(
      const CreateInteractionCommand(
        partyName: 'BrightSure',
        summary: 'Unrelated call',
      ),
    );
    await tester.pumpWidget(MyLittleCrmApp(service: service));
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'fff');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Premium disputed fff'));
    await tester.pumpAndSettle();
    expect(find.text('Edit interaction'), findsOneWidget);
    expect(find.text('Unrelated call'), findsNothing);
    final summary = tester.widget<TextFormField>(
      find.byKey(const Key('summary')),
    );
    expect(summary.controller!.text, 'Premium disputed fff');
  });
  testWidgets('refreshes the current search after editing a result', (
    tester,
  ) async {
    final service = CrmService(
      parties: MemoryPartyRepository(),
      interactions: MemoryInteractionRepository(),
      clock: FixedClock(DateTime.utc(2026, 11, 11)),
    );
    await service.createInteraction(
      const CreateInteractionCommand(
        partyName: 'BrightSure',
        summary: 'Premium disputed',
      ),
    );
    await tester.pumpWidget(MyLittleCrmApp(service: service));
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'premium');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Premium disputed'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('summary')), 'Claim settled');
    await tester.ensureVisible(find.text('Save interaction'));
    await tester.tap(find.text('Save interaction'));
    await tester.pumpAndSettle();
    expect(find.text('Premium disputed'), findsNothing);
    expect(find.text('BrightSure'), findsNothing);
    expect(find.text('premium'), findsOneWidget);
  });
}

class _FailingSearchRepository extends MemoryInteractionRepository {
  bool fail = true;
  @override
  Future<List<Interaction>> search(String query) async {
    if (fail) throw StateError('Disk unavailable');
    return super.search(query);
  }
}
