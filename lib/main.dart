import 'package:flutter/widgets.dart';

import 'app.dart';
import 'core/clock.dart';
import 'data/local/app_database.dart';
import 'data/local/interaction_repository.dart';
import 'data/local/party_repository.dart';
import 'demo/demo_data.dart';
import 'demo/demo_mode.dart';
import 'domain/crm_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The demo (and every web build) never touches the real ledger: it gets a
  // fresh in-memory database, seeded with sample records, on each launch.
  final database = isDemoMode
      ? await AppDatabase.inMemory()
      : await AppDatabase.open();
  final service = CrmService(
    parties: LocalPartyRepository(database),
    interactions: LocalInteractionRepository(database),
    clock: const SystemClock(),
  );
  if (isDemoMode) await seedDemoLedger(service);
  runApp(MyLittleCrmApp(service: service, demo: isDemoMode));
}
