import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/core/clock.dart';
import 'package:my_little_crm/domain/crm_service.dart';
import 'package:my_little_crm/domain/repositories.dart';
import 'package:my_little_crm/features/interactions/interaction_editor.dart';

void main() {
  // Regression for #22: on Android (edge-to-edge) the editor sheet's Save
  // button was drawn underneath the system navigation bar.
  testWidgets('editor sheet keeps Save above the system navigation bar', (
    tester,
  ) async {
    const navBarHeight = 48.0;
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2408);
    tester.view.padding = const FakeViewPadding(bottom: navBarHeight * 3);
    tester.view.viewPadding = const FakeViewPadding(bottom: navBarHeight * 3);
    addTearDown(tester.view.reset);

    final service = CrmService(
      parties: MemoryPartyRepository(),
      interactions: MemoryInteractionRepository(),
      clock: FixedClock(DateTime.utc(2026)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => editInteraction(context, service),
              child: const Text('Add'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    // Scroll to the very end of the sheet.
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();

    final screenHeight = tester.view.physicalSize.height / 3;
    final save = tester.getRect(find.text('Save interaction'));
    final button = tester.getRect(
      find.ancestor(
        of: find.text('Save interaction'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(save.bottom, lessThanOrEqualTo(screenHeight - navBarHeight));
    expect(button.bottom, lessThanOrEqualTo(screenHeight - navBarHeight));
  });
}
