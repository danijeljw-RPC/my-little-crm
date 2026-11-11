import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/app.dart';

void main() {
  testWidgets('shows the My Little CRM home shell', (tester) async {
    await tester.pumpWidget(const MyLittleCrmApp());

    expect(find.text('My Little CRM'), findsOneWidget);
    expect(find.text('Interactions'), findsOneWidget);
  });
}
