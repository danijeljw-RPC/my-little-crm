import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/app.dart';
import 'package:my_little_crm/core/clock.dart';
import 'package:my_little_crm/domain/crm_service.dart';
import 'package:my_little_crm/domain/models.dart';
import 'package:my_little_crm/domain/repositories.dart';

void main() {
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
  testWidgets('refreshes the current search after editing from history', (
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
    await tester.tap(find.text('Premium disputed'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('summary')), 'Claim settled');
    await tester.ensureVisible(find.text('Save interaction'));
    await tester.tap(find.text('Save interaction'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Premium disputed'), findsNothing);
    expect(find.text('BrightSure'), findsNothing);
    expect(find.text('premium'), findsOneWidget);
  });
}
