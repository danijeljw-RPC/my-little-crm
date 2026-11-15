// Guards where the live database lives and the macOS sandbox it relies on
// (#54). See the "Where the database lives" section of
// docs/PLATFORM-SETTINGS.md.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_crm/data/local/app_database.dart';
import 'package:my_little_crm/data/local/party_repository.dart';

Map<String, String> _plist(String path) {
  final source = File(path).readAsStringSync();
  return {
    for (final m in RegExp(
      r'<key>([^<]+)</key>\s*<(true|false)\s*/>',
    ).allMatches(source))
      m.group(1)!: m.group(2)!,
  };
}

void main() {
  group('database location', () {
    test('is crm.sqlite in the Application Support directory', () async {
      final path = await AppDatabase.defaultPath(
        supportDirectory: () async => Directory('/support'),
      );
      // Renaming the file or folder would orphan every existing ledger.
      expect(path, '/support/crm.sqlite');
      expect(AppDatabase.fileName, 'crm.sqlite');
    });

    test('opens through the default path and keeps data on reopen', () async {
      final directory = await Directory.systemTemp.createTemp('crm-loc-');
      addTearDown(() => directory.delete(recursive: true));
      // A support directory that does not exist yet, as on first launch.
      final support = Directory('${directory.path}/Application Support/app');
      final path = await AppDatabase.defaultPath(
        supportDirectory: () async => support,
      );

      final first = await AppDatabase.open(path: path, useFfi: true);
      await LocalPartyRepository(first).findOrCreate('Persisted Co');
      await first.close();
      final reopened = await AppDatabase.open(path: path, useFfi: true);
      addTearDown(reopened.close);

      expect(File(path).existsSync(), isTrue);
      expect((await LocalPartyRepository(reopened).list()).map((p) => p.name), [
        'Persisted Co',
      ]);
    });

    test('is never resolved from the app bundle or working directory', () {
      final source = File('lib/data/local/app_database.dart')
          .readAsStringSync();
      expect(source, contains('getApplicationSupportDirectory'));
      for (final forbidden in [
        'Platform.resolvedExecutable',
        'Platform.script',
        'Directory.current',
        'getTemporaryDirectory',
        'NSBundle',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });

  group('macOS App Sandbox', () {
    test('release build is sandboxed with user-selected file access only', () {
      expect(_plist('macos/Runner/Release.entitlements'), {
        'com.apple.security.app-sandbox': 'true',
        'com.apple.security.files.user-selected.read-write': 'true',
      });
    });

    test('debug and profile builds are sandboxed too', () {
      final debug = _plist('macos/Runner/DebugProfile.entitlements');
      expect(debug['com.apple.security.app-sandbox'], 'true');
      expect(
        debug['com.apple.security.files.user-selected.read-write'],
        'true',
      );
    });

    test('no entitlement exceptions that App Review would reject', () {
      for (final path in [
        'macos/Runner/Release.entitlements',
        'macos/Runner/DebugProfile.entitlements',
      ]) {
        final source = File(path).readAsStringSync();
        expect(source, isNot(contains('temporary-exception')), reason: path);
        expect(source, isNot(contains('files.all')), reason: path);
        expect(source, isNot(contains('home-relative-path')), reason: path);
      }
    });

    test('release configuration signs with the release entitlements', () {
      final project = File('macos/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      expect(
        project,
        contains('CODE_SIGN_ENTITLEMENTS = Runner/Release.entitlements;'),
      );
    });
  });
}
