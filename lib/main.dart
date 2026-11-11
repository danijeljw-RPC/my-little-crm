import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/local/app_database.dart';
import 'data/local/party_repository.dart';
import 'data/local/interaction_repository.dart';
import 'domain/crm_service.dart';
import 'core/clock.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = await AppDatabase.open();
  final service = CrmService(
    parties: LocalPartyRepository(database),
    interactions: LocalInteractionRepository(database),
    clock: const SystemClock(),
  );
  runApp(ProviderScope(child: MyLittleCrmApp(service: service)));
}
