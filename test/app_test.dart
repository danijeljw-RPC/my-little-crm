import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/app.dart';

void main() {
  testWidgets('shows the My Little CRM home shell', (tester) async {
    await tester.pumpWidget(const MyLittleCrmApp());

    expect(find.text('My Little CRM'), findsOneWidget);
    expect(find.text('No interactions yet'), findsOneWidget);
  });

  testWidgets('records an interaction from the quick-entry form', (
    tester,
  ) async {
    await tester.pumpWidget(const MyLittleCrmApp());
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
}
