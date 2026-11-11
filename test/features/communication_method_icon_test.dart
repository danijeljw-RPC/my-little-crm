import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/app.dart';
import 'package:my_little_crm/core/clock.dart';
import 'package:my_little_crm/domain/crm_service.dart';
import 'package:my_little_crm/domain/models.dart';
import 'package:my_little_crm/domain/repositories.dart';
import 'package:my_little_crm/features/interactions/communication_method_icon.dart';

void main() {
  test('every communication method has a distinct icon', () {
    final icons = CommunicationMethod.values.map((m) => m.icon).toSet();
    expect(icons, hasLength(CommunicationMethod.values.length));
  });

  testWidgets('method dropdown shows an icon beside each option', (
    tester,
  ) async {
    final service = CrmService(
      parties: MemoryPartyRepository(),
      interactions: MemoryInteractionRepository(),
      clock: FixedClock(DateTime.utc(2026, 11, 11)),
    );
    await tester.pumpWidget(MyLittleCrmApp(service: service));
    await tester.tap(find.text('Add interaction'));
    await tester.pumpAndSettle();
    // Selected value shows its icon.
    expect(find.byIcon(CommunicationMethod.phone.icon), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<CommunicationMethod>));
    await tester.pumpAndSettle();
    for (final method in CommunicationMethod.values) {
      expect(find.byIcon(method.icon), findsWidgets, reason: method.name);
    }
  });
}
