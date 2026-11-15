import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/app.dart';
import 'package:my_little_crm/core/clock.dart';
import 'package:my_little_crm/core/date_format.dart';
import 'package:my_little_crm/domain/crm_service.dart';
import 'package:my_little_crm/domain/models.dart';

void main() {
  // Local wall-clock values, so the expectations hold in any test time zone.
  final now = DateTime(2026, 11, 15, 16, 30);
  AppDateFormat format(String locale, {bool use24 = false}) =>
      AppDateFormat(locale: locale, use24HourFormat: use24, now: now);

  test('relative labels for nearby days', () {
    final f = format('en_AU');
    expect(f.date(DateTime(2026, 11, 15, 1)), 'Today');
    expect(f.date(DateTime(2026, 11, 14, 23, 59)), 'Yesterday');
    expect(f.date(DateTime(2026, 11, 16)), 'Tomorrow');
    expect(f.dateTime(DateTime(2026, 11, 15, 14, 5)), 'Today 2:05\u202fpm');
  });

  test('follows the locale for day order, names and the 24-hour setting', () {
    final day = DateTime(2026, 11, 17, 14, 5);
    expect(format('en_US').dateTime(day), 'Tue, Nov 17 2:05\u202fPM');
    expect(format('en_AU').dateTime(day), 'Tue, 17 Nov 2:05\u202fpm');
    expect(format('en_AU', use24: true).dateTime(day), 'Tue, 17 Nov 14:05');
    expect(format('de_DE').dateTime(day), 'Di., 17. Nov. 14:05');
    expect(format('en_US').date(DateTime(2025, 3, 4)), 'Mar 4, 2025');
    expect(format('en_AU').date(DateTime(2025, 3, 4)), '4 Mar 2025');
  });

  test('unknown locales fall back to their language, then en_US', () {
    expect(format('fr_XX').locale, 'fr');
    expect(format('zz').locale, 'en_US');
  });

  test('documents use absolute dates', () {
    final f = format('en_AU', use24: true);
    expect(f.fullDateTime(DateTime(2026, 11, 15, 9)), 'Sun, 15 Nov 2026 09:00');
  });

  testWidgets('home, history and search use the shared formatter', (
    tester,
  ) async {
    final service = CrmService.inMemory(clock: FixedClock(now.toUtc()));
    await service.createInteraction(
      CreateInteractionCommand(
        partyName: 'BrightSure',
        summary: 'Quote call',
        timestamp: DateTime(2026, 11, 15, 14, 5).toUtc(),
      ),
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(400, 800),
          alwaysUse24HourFormat: true,
        ),
        child: MyLittleCrmApp(service: service, dateLocale: 'en-AU'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Today 14:05'), findsOneWidget);

    await tester.tap(find.text('Quote call'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Today 14:05 · phone'), findsOneWidget);
    expect(find.textContaining('.000'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'quote');
    await tester.pumpAndSettle();
    expect(find.text('Today 14:05 · phone'), findsOneWidget);
  });
}
