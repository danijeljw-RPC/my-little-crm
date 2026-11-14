// Renders Google Play store screenshots of the real app with sample data.
//
// Not part of the normal test suite (it lives outside test/). Regenerate with:
//
//   tool/store_listing/generate.sh
//
// The PNGs are written via golden files into tool/store_listing/out/ and then
// copied into docs/play-store/ by the generate script.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/app.dart';
import 'package:my_little_crm/core/clock.dart';
import 'package:my_little_crm/domain/crm_service.dart';
import 'package:my_little_crm/domain/models.dart';
import 'package:my_little_crm/domain/repositories.dart';

class _Device {
  const _Device(this.folder, this.physicalSize, this.devicePixelRatio);
  final String folder;
  final Size physicalSize;
  final double devicePixelRatio;
}

// All sizes are exactly 9:16 portrait, as Google Play requires.
const _devices = [
  _Device('phone', Size(1080, 1920), 2.625), // ~411 x 731 dp
  _Device('tablet-7in', Size(1080, 1920), 1.875), // 576 x 1024 dp
  _Device('tablet-10in', Size(1620, 2880), 2.025), // 800 x ~1422 dp
];

// Fixed "now" so the sample data and form dates are deterministic.
final _now = DateTime(2026, 11, 14, 10, 30);

Future<void> _loadFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) {
    throw StateError('FLUTTER_ROOT is not set; run via generate.sh');
  }
  final fonts = '$flutterRoot/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = File('$fonts/$file').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

Future<CrmService> _seededService() async {
  final service = CrmService(
    parties: MemoryPartyRepository(),
    interactions: MemoryInteractionRepository(),
    clock: FixedClock(_now),
  );
  Future<void> add(
    String party,
    String summary,
    DateTime at, {
    CommunicationMethod method = CommunicationMethod.phone,
    String? contact,
    List<String> refs = const [],
    String? commitment,
    DateTime? followUp,
  }) => service.createInteraction(
    CreateInteractionCommand(
      partyName: party,
      summary: summary,
      timestamp: at,
      method: method,
      contactName: contact,
      referenceNumbers: refs,
      commitment: commitment,
      followUpDueAt: followUp,
    ),
  );

  await add(
    'Brightwave Energy',
    'Disputed estimated meter reading',
    DateTime(2026, 11, 13, 14, 20),
    contact: 'Priya',
    refs: ['CASE-48213'],
    commitment: 'Bill to be re-issued from an actual reading',
    followUp: DateTime(2026, 11, 20, 9),
  );
  await add(
    'Harbour Bank',
    'Refund for duplicate card charge',
    DateTime(2026, 11, 12, 11, 5),
    method: CommunicationMethod.chat,
    contact: 'Marcus',
    refs: ['TXN-99021'],
    commitment: 'Refund within 5 business days',
    followUp: DateTime(2026, 11, 19, 9),
  );
  await add(
    'BrightSure Insurance',
    'Revised home insurance quote promised',
    DateTime(2026, 11, 11, 16, 40),
    method: CommunicationMethod.email,
    contact: 'Alex Chen',
    refs: ['Q-301177'],
    commitment: 'New quote emailed by Friday',
    followUp: DateTime(2026, 11, 15, 9),
  );
  await add(
    'Northside Property Management',
    'Leaking kitchen tap reported',
    DateTime(2026, 11, 10, 9, 15),
    contact: 'Dana',
    refs: ['MR-5520'],
    commitment: 'Plumber booked for next week',
    followUp: DateTime(2026, 11, 18, 9),
  );
  await add(
    'Swift Mobile',
    'Plan downgrade confirmed',
    DateTime(2026, 11, 7, 13, 0),
    method: CommunicationMethod.chat,
    refs: ['SM-77310'],
    commitment: 'New plan starts next billing cycle',
  );
  await add(
    'Brightwave Energy',
    'Asked for refund of late fee',
    DateTime(2026, 11, 4, 10, 30),
    contact: 'Tom',
    refs: ['CASE-47950'],
    commitment: 'Late fee waived as a one-off',
  );
  await add(
    'City Council',
    'Bin replacement requested',
    DateTime(2026, 11, 3, 15, 45),
    method: CommunicationMethod.email,
    refs: ['CRM-208841'],
    commitment: 'New bin delivered within 10 days',
  );
  await add(
    'Brightwave Energy',
    'Moved to monthly billing',
    DateTime(2026, 10, 21, 12, 10),
    method: CommunicationMethod.letter,
    refs: ['ACC-1182-339'],
  );
  return service;
}

Future<void> _pumpApp(WidgetTester tester, _Device device) async {
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
  tester.view.physicalSize = device.physicalSize;
  tester.view.devicePixelRatio = device.devicePixelRatio;
  addTearDown(tester.view.reset);
  final service = await tester.runAsync(_seededService);
  await tester.pumpWidget(MyLittleCrmApp(service: service));
  await tester.pumpAndSettle();
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Future<void> _shoot(WidgetTester tester, _Device device, String name) async {
  // Tests draw shadows as black outlines by default; render real ones for the
  // capture, then restore the flag (the test framework checks it is unset).
  debugDisableShadows = false;
  try {
    for (final element in find.byType(MaterialApp).evaluate()) {
      _markSubtreeNeedsPaint(element);
    }
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('out/${device.folder}/$name.png'),
    );
  } finally {
    debugDisableShadows = true;
  }
}

void _markSubtreeNeedsPaint(Element element) {
  element.renderObject?.markNeedsPaint();
  element.visitChildren(_markSubtreeNeedsPaint);
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    // Render like a real device: no debug banner, real shadows (tests draw
    // them as black outlines by default) and no keyboard focus rings.
    WidgetsApp.debugAllowBannerOverride = false;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
  });

  for (final device in _devices) {
    group(device.folder, () {
      testWidgets('01 interactions', (tester) async {
        await _pumpApp(tester, device);
        await _shoot(tester, device, '01-interactions');
      });

      testWidgets('02 add interaction', (tester) async {
        await _pumpApp(tester, device);
        await tester.tap(find.text('Add interaction'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('party-name')),
          'Harbour Bank',
        );
        await tester.enterText(
          find.byKey(const Key('summary')),
          'Called to chase the duplicate charge refund',
        );
        Future<void> fill(String label, String text) =>
            tester.enterText(find.widgetWithText(TextFormField, label), text);
        await fill('Contact name (optional)', 'Marcus');
        await fill('Reference numbers (comma separated)', 'TXN-99021');
        await fill(
          'Agreement or promise (optional)',
          'Refund escalated, 2 more days',
        );
        // Dismiss the party-name suggestions and the cursor.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await _shoot(tester, device, '02-add-interaction');
      });

      testWidgets('03 follow-ups', (tester) async {
        await _pumpApp(tester, device);
        await _tapTab(tester, 'Follow-ups');
        await _shoot(tester, device, '03-follow-ups');
      });

      testWidgets('04 party history', (tester) async {
        await _pumpApp(tester, device);
        await _tapTab(tester, 'Parties');
        await tester.tap(find.text('Brightwave Energy'));
        await tester.pumpAndSettle();
        await _shoot(tester, device, '04-party-history');
      });

      testWidgets('05 search', (tester) async {
        await _pumpApp(tester, device);
        await _tapTab(tester, 'Search');
        await tester.enterText(find.byType(TextField), 'refund');
        await tester.pumpAndSettle();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await _shoot(tester, device, '05-search');
      });

      testWidgets('06 parties', (tester) async {
        await _pumpApp(tester, device);
        await _tapTab(tester, 'Parties');
        await _shoot(tester, device, '06-parties');
      });
    });
  }
}
