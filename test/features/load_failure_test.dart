import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/app.dart';
import 'package:my_little_crm/core/clock.dart';
import 'package:my_little_crm/domain/crm_service.dart';
import 'package:my_little_crm/domain/models.dart';
import 'package:my_little_crm/domain/repositories.dart';
import 'package:my_little_crm/features/parties/party_list_screen.dart';
import 'package:my_little_crm/features/parties/party_history_screen.dart';
import 'package:my_little_crm/features/follow_ups/follow_ups_screen.dart';

class _UnavailableParties extends MemoryPartyRepository {
  bool fail = true;
  @override
  Future<List<Party>> list() async {
    if (fail) throw StateError('Storage unavailable');
    return super.list();
  }
}

class _UnavailableInteractions extends MemoryInteractionRepository {
  bool fail = true;
  @override
  Future<List<Interaction>> forParty(PartyId partyId) async {
    if (fail) throw StateError('Storage unavailable');
    return super.forParty(partyId);
  }

  @override
  Future<List<Interaction>> openFollowUps() async {
    if (fail) throw StateError('Storage unavailable');
    return super.openFollowUps();
  }
}

void main() {
  for (final screen in ['home', 'parties', 'history', 'follow-ups']) {
    testWidgets('$screen shows load failures and retries', (tester) async {
      final parties = _UnavailableParties();
      final interactions = _UnavailableInteractions();
      final service = CrmService(
        parties: parties,
        interactions: interactions,
        clock: FixedClock(DateTime.utc(2026)),
      );
      final party = await parties.findOrCreate('BrightSure');
      final item = await service.createInteraction(
        CreateInteractionCommand(
          partyName: 'BrightSure',
          summary: 'Request quote',
          followUpDueAt: DateTime.utc(2027),
        ),
      );
      final Widget widget = switch (screen) {
        'home' => MyLittleCrmApp(service: service),
        'parties' => MaterialApp(
          home: Scaffold(body: PartyListScreen(service: service)),
        ),
        'history' => MaterialApp(
          home: PartyHistoryScreen(service: service, party: party),
        ),
        _ => MaterialApp(
          home: Scaffold(body: FollowUpsScreen(service: service)),
        ),
      };
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('Retry'), findsOneWidget);
      parties.fail = false;
      interactions.fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
      expect(
        find.text(screen == 'parties' ? 'BrightSure' : item.summary),
        findsOneWidget,
      );
    });
  }
}
