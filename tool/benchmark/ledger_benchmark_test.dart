// Large-ledger benchmark for the home list, follow-ups and search (#39).
//
//   flutter test tool/benchmark/ledger_benchmark_test.dart
//
// Seeds an on-disk SQLite ledger (FFI) with 50,000 interactions across 2,000
// parties, then reports the median of several timed runs per operation. It is
// kept out of test/ so the regular suite and CI stay fast. Record results in
// docs/delivery/STAGE-1-REVIEW.md.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/core/clock.dart';
import 'package:my_little_crm/data/local/app_database.dart';
import 'package:my_little_crm/domain/crm_service.dart';
import 'package:my_little_crm/features/export/history_export_service.dart';
import 'package:my_little_crm/data/local/interaction_repository.dart';
import 'package:my_little_crm/data/local/party_repository.dart';
import 'package:my_little_crm/domain/models.dart';

const partyCount = 2000;
const interactionCount = 50000;
const runs = 7;

void main() {
  // The PDF report loads its font from the asset bundle.
  TestWidgetsFlutterBinding.ensureInitialized();
  test('large ledger timings', timeout: const Timeout(Duration(minutes: 15)), () async {
    final directory = await Directory.systemTemp.createTemp('crm-bench-');
    addTearDown(() => directory.delete(recursive: true));
    final db = await AppDatabase.open(
      path: '${directory.path}/bench.sqlite',
      useFfi: true,
    );
    addTearDown(db.close);
    final parties = LocalPartyRepository(db);
    final interactions = LocalInteractionRepository(db);

    final seed = Stopwatch()..start();
    final random = Random(42);
    final ids = <Party>[];
    for (var p = 0; p < partyCount; p++) {
      ids.add(await parties.restore(Party(id: 'p$p', name: 'Party $p Ltd')));
    }
    final base = DateTime.utc(2020);
    final batch = <Interaction>[];
    for (var i = 0; i < interactionCount; i++) {
      final time = base.add(Duration(minutes: random.nextInt(3000000)));
      batch.add(
        Interaction(
          id: 'i${i.toString().padLeft(6, '0')}',
          partyId: ids[random.nextInt(partyCount)].id,
          summary:
              'Call $i about ${['refund', 'premium', 'invoice', 'claim'][i % 4]} '
              'and next steps',
          timestamp: time,
          createdAt: time,
          contactName: i % 3 == 0 ? 'Contact ${i % 500}' : null,
          referenceNumbers: i % 2 == 0 ? ['CASE-$i'] : const [],
          followUp: i % 25 == 0
              ? FollowUp(
                  dueAt: time.add(const Duration(days: 7)),
                  status: i % 50 == 0
                      ? FollowUpStatus.completed
                      : FollowUpStatus.open,
                )
              : null,
        ),
      );
      if (batch.length == 5000) {
        await interactions.saveAll(batch);
        batch.clear();
      }
    }
    await interactions.saveAll(batch);
    // ignore: avoid_print
    print('Seeded $interactionCount interactions in ${seed.elapsed}');

    Future<void> measure(String name, Future<Object?> Function() body) async {
      await body(); // warm-up
      final samples = <int>[];
      for (var r = 0; r < runs; r++) {
        final watch = Stopwatch()..start();
        await body();
        samples.add(watch.elapsedMicroseconds);
      }
      samples.sort();
      // ignore: avoid_print
      print(
        '${name.padRight(46)} median ${(samples[runs ~/ 2] / 1000).toStringAsFixed(1).padLeft(8)} ms'
        '  (min ${(samples.first / 1000).toStringAsFixed(1)} ms)',
      );
    }

    final firstPage = await interactions.recent();
    final cursor = RecentCursor.after(firstPage.last.interaction);
    await measure('1.0.0 home reload (N+1 over all parties)', () async {
      final all = <Interaction>[];
      for (final party in await parties.list()) {
        all.addAll(await interactions.forParty(party.id));
      }
      all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return all;
    });
    await measure('1.1.0 home first page (50)', interactions.recent);
    await measure(
      '1.1.0 home next page (50, keyset)',
      () => interactions.recent(after: cursor),
    );
    await measure('open follow-ups', interactions.openFollowUps);
    await measure(
      'party history (one party)',
      () => interactions.forParty('p7'),
    );
    for (final query in [
      'CASE-24680', // exact reference
      'refund', // FTS word, many hits
      'Party 1234', // party name substring
      'Contact 42', // contact substring
      'zzzz-no-match',
    ]) {
      await measure('search "$query"', () => interactions.search(query));
    }
    expect(await interactions.count(), interactionCount);

    // Whole-ledger PDF report (#52): one timed run, it is too slow to repeat.
    final service = CrmService(
      parties: parties,
      interactions: interactions,
      clock: const SystemClock(),
    );
    final pdfWatch = Stopwatch()..start();
    final report = await HistoryExportService(service).exportLedgerPdf();
    pdfWatch.stop();
    // ignore: avoid_print
    print(
      '${'ledger PDF report (#52)'.padRight(46)} '
      '${(pdfWatch.elapsedMilliseconds / 1000).toStringAsFixed(1).padLeft(8)} s'
      '  (${(report.bytes.length / 1024 / 1024).toStringAsFixed(1)} MB)',
    );
  });
}
