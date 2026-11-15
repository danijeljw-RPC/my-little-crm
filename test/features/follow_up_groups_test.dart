import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/app.dart';
import 'package:my_little_crm/core/clock.dart';
import 'package:my_little_crm/domain/crm_service.dart';
import 'package:my_little_crm/domain/models.dart';

// Local wall-clock values so grouping holds in any test time zone.
final _now = DateTime(2026, 11, 15, 12);

Future<CrmService> _seed() async {
  final service = CrmService.inMemory(clock: FixedClock(_now.toUtc()));
  Future<void> add(String summary, DateTime due, {bool hasTime = false}) =>
      service.createInteraction(
        CreateInteractionCommand(
          partyName: 'Party $summary',
          summary: summary,
          followUpDueAt: due.toUtc(),
          followUpHasTime: hasTime,
        ),
      );
  await add('Yesterday day-only', DateTime(2026, 11, 14));
  await add('Today 9am timed', DateTime(2026, 11, 15, 9), hasTime: true);
  await add('Today day-only', DateTime(2026, 11, 15));
  await add('Today 5pm timed', DateTime(2026, 11, 15, 17), hasTime: true);
  await add('Next week', DateTime(2026, 11, 22));
  return service;
}

void main() {
  group('FollowUp.urgency', () {
    test('day-only items stay due today until the end of the day', () {
      final dayOnly = FollowUp(dueAt: DateTime(2026, 11, 15).toUtc());
      expect(dayOnly.urgency(_now), FollowUpUrgency.today);
      expect(
        dayOnly.urgency(DateTime(2026, 11, 15, 23, 59)),
        FollowUpUrgency.today,
      );
      expect(dayOnly.urgency(DateTime(2026, 11, 16)), FollowUpUrgency.overdue);
      expect(dayOnly.urgency(DateTime(2026, 11, 14)), FollowUpUrgency.upcoming);
    });

    test('timed items become overdue at their time', () {
      final timed = FollowUp(
        dueAt: DateTime(2026, 11, 15, 14).toUtc(),
        hasTime: true,
      );
      expect(timed.urgency(DateTime(2026, 11, 15, 13)), FollowUpUrgency.today);
      expect(
        timed.urgency(DateTime(2026, 11, 15, 14)),
        FollowUpUrgency.overdue,
      );
    });
  });

  testWidgets('groups overdue, today and upcoming, and badges the count', (
    tester,
  ) async {
    final service = await _seed();
    await tester.pumpWidget(MyLittleCrmApp(service: service, dateLocale: 'en'));
    await tester.pumpAndSettle();
    // Badge on the navigation: yesterday's and 9am today's items.
    expect(find.bySemanticsLabel(RegExp(r'^2 overdue')), findsOneWidget);

    await tester.tap(find.text('Follow-ups'));
    await tester.pumpAndSettle();
    final order = [
      'Overdue (2)',
      'Yesterday day-only',
      'Today 9am timed',
      'Due today (2)',
      'Today 5pm timed',
      'Today day-only',
      'Upcoming (1)',
      'Next week',
    ];
    final ys = [
      for (final text in order) tester.getTopLeft(find.text(text)).dy,
    ];
    expect(ys, orderedEquals([...ys]..sort()));

    // Overdue state is spelled out, not only coloured.
    expect(find.textContaining('Overdue · was due'), findsNWidgets(2));
    expect(find.text('Due Today'), findsOneWidget);

    await tester.tap(find.byTooltip('Complete follow-up').first);
    await tester.pumpAndSettle();
    expect(find.text('Overdue (1)'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^1 overdue')), findsOneWidget);
  });

  testWidgets('an optional due time can be set in the editor', (tester) async {
    final service = CrmService.inMemory(clock: FixedClock(_now.toUtc()));
    await tester.pumpWidget(MyLittleCrmApp(service: service, dateLocale: 'en'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add interaction'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('party-name')), 'BrightSure');
    await tester.enterText(find.byKey(const Key('summary')), 'Call back');
    await tester.ensureVisible(find.text('Add follow-up date'));
    await tester.tap(find.text('Add follow-up date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('16'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(
      find.text('Without a time, it is due by the end of that day.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(const Key('follow-up-time')));
    await tester.tap(find.byKey(const Key('follow-up-time')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK')); // default 9:00 AM
    await tester.pumpAndSettle();
    expect(find.textContaining('Follow-up: Tomorrow 9:00'), findsOneWidget);
    await tester.ensureVisible(find.text('Save interaction'));
    await tester.tap(find.text('Save interaction'));
    await tester.pumpAndSettle();

    final saved = (await service.outstandingFollowUps()).single.followUp!;
    expect(saved.hasTime, isTrue);
    expect(saved.dueAt.toLocal(), DateTime(2026, 11, 16, 9));
  });
}
