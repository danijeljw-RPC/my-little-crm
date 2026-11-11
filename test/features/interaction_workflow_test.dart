import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/app.dart';
import 'package:my_little_crm/core/clock.dart';
import 'package:my_little_crm/domain/crm_service.dart';
import 'package:my_little_crm/domain/repositories.dart';

void main() {
  testWidgets('records an interaction and retains it in the party timeline', (tester) async {
    final service = CrmService(
      parties: MemoryPartyRepository(),
      interactions: MemoryInteractionRepository(),
      clock: FixedClock(DateTime.utc(2026, 11, 11, 10)),
    );

    await tester.pumpWidget(MyLittleCrmApp(service: service));
    await tester.tap(find.text('Add interaction'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('party-name')), 'BrightSure Insurance');
    await tester.enterText(find.byKey(const Key('summary')), 'Revised quote promised');
    await tester.tap(find.text('Save interaction'));
    await tester.pumpAndSettle();

    expect(find.text('BrightSure Insurance'), findsOneWidget);
    expect(find.text('Revised quote promised'), findsOneWidget);
  });
}
