// Guards the app-identity settings that live in native platform files.
//
// Several of these values reference each other across files, so renaming one
// (for example the macOS app name or the Android package) without the others
// breaks native builds or native tests. See docs/PLATFORM-SETTINGS.md for
// what each value controls and where it lives.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The user-facing app name every platform should display.
const appDisplayName = 'My Little CRM';

/// The single app ID shared by every platform (Apple bundle ID, Android
/// applicationId and namespace, Linux APPLICATION_ID).
const appId = 'com.repasscloud.mylittlecrm';

/// Company shown in copyright notices and Windows file properties.
const companyName = 'RePass Cloud Pty Ltd';

String _read(String path) => File(path).readAsStringSync();

/// Returns every capture of [pattern]'s first group in the file at [path].
List<String> _all(String path, String pattern) => RegExp(
  pattern,
  multiLine: true,
).allMatches(_read(path)).map((m) => m.group(1)!.trim()).toList();

String _one(String path, String pattern) {
  final values = _all(path, pattern).toSet();
  expect(
    values,
    hasLength(1),
    reason: 'Expected one value for $pattern in $path',
  );
  return values.single;
}

void main() {
  group('macOS', () {
    const appInfo = 'macos/Runner/Configs/AppInfo.xcconfig';
    const project = 'macos/Runner.xcodeproj/project.pbxproj';

    test('native test host points at the built app name', () {
      final productName = _one(appInfo, r'^PRODUCT_NAME = (.+)$');
      final hosts = _all(project, r'TEST_HOST = "(.+)";');
      expect(hosts, isNotEmpty);
      for (final host in hosts) {
        expect(
          host,
          '\$(BUILT_PRODUCTS_DIR)/$productName.app/'
          '\$(BUNDLE_EXECUTABLE_FOLDER_PATH)/$productName',
        );
      }
    });

    test('RunnerTests bundle id extends the app bundle id', () {
      final appId = _one(appInfo, r'^PRODUCT_BUNDLE_IDENTIFIER = (.+)$');
      final testIds = _all(
        project,
        r'PRODUCT_BUNDLE_IDENTIFIER = (.+\.RunnerTests);',
      );
      expect(testIds, isNotEmpty);
      expect(testIds.toSet(), {'$appId.RunnerTests'});
    });
  });

  group('iOS', () {
    const project = 'ios/Runner.xcodeproj/project.pbxproj';

    test('RunnerTests bundle id extends the app bundle id', () {
      final ids = _all(project, r'PRODUCT_BUNDLE_IDENTIFIER = (.+);');
      final appIds = ids.where((id) => !id.endsWith('.RunnerTests')).toSet();
      final testIds = ids.where((id) => id.endsWith('.RunnerTests')).toSet();
      expect(appIds, hasLength(1));
      expect(testIds, {'${appIds.single}.RunnerTests'});
    });
  });

  group('Android', () {
    const gradle = 'android/app/build.gradle.kts';

    test('MainActivity package and folder match the namespace', () {
      final namespace = _one(gradle, r'^\s*namespace = "(.+)"$');
      final activity = File(
        'android/app/src/main/kotlin/'
        '${namespace.replaceAll('.', '/')}/MainActivity.kt',
      );
      expect(
        activity.existsSync(),
        isTrue,
        reason: 'MainActivity.kt must live in the folder for $namespace',
      );
      expect(activity.readAsStringSync(), contains('package $namespace\n'));
    });
  });

  group('Windows', () {
    test('OriginalFilename matches the CMake binary name', () {
      final binary = _one(
        'windows/CMakeLists.txt',
        r'^set\(BINARY_NAME "(.+)"\)$',
      );
      final original = _one(
        'windows/runner/Runner.rc',
        r'VALUE "OriginalFilename", "(.+)" "\\0"',
      );
      expect(original, '$binary.exe');
    });
  });

  group('shared identity', () {
    test('every platform uses the same app ID', () {
      final ids = {
        'macOS': _one(
          'macos/Runner/Configs/AppInfo.xcconfig',
          r'^PRODUCT_BUNDLE_IDENTIFIER = (.+)$',
        ),
        'iOS': _all(
          'ios/Runner.xcodeproj/project.pbxproj',
          r'PRODUCT_BUNDLE_IDENTIFIER = (.+);',
        ).where((id) => !id.endsWith('.RunnerTests')).toSet().single,
        'Android applicationId': _one(
          'android/app/build.gradle.kts',
          r'^\s*applicationId = "(.+)"$',
        ),
        'Android namespace': _one(
          'android/app/build.gradle.kts',
          r'^\s*namespace = "(.+)"$',
        ),
        'Linux': _one(
          'linux/CMakeLists.txt',
          r'^set\(APPLICATION_ID "(.+)"\)$',
        ),
      };
      for (final entry in ids.entries) {
        expect(entry.value, appId, reason: entry.key);
      }
    });

    test('copyright and company name are set', () {
      expect(
        _one(
          'macos/Runner/Configs/AppInfo.xcconfig',
          r'^PRODUCT_COPYRIGHT = (.+)$',
        ),
        contains(companyName),
      );
      expect(
        _one('windows/runner/Runner.rc', r'VALUE "CompanyName", "(.+)" "\\0"'),
        companyName,
      );
      expect(
        _one(
          'windows/runner/Runner.rc',
          r'VALUE "LegalCopyright", "(.+)" "\\0"',
        ),
        contains(companyName),
      );
    });

    const files = [
      'macos/Runner/Configs/AppInfo.xcconfig',
      'macos/Runner.xcodeproj/project.pbxproj',
      'ios/Runner.xcodeproj/project.pbxproj',
      'android/app/build.gradle.kts',
      'windows/runner/Runner.rc',
      'linux/CMakeLists.txt',
    ];
    for (final path in files) {
      test('$path has no flutter create placeholder', () {
        expect(_read(path), isNot(contains('com.example')));
      });
    }

    test('every platform shows "$appDisplayName"', () {
      expect(
        _one(
          'ios/Runner/Info.plist',
          r'<key>CFBundleDisplayName</key>\s*<string>(.+)</string>',
        ),
        appDisplayName,
      );
      expect(
        _one('macos/Runner/Configs/AppInfo.xcconfig', r'^PRODUCT_NAME = (.+)$'),
        appDisplayName,
      );
      expect(
        _one(
          'android/app/src/main/AndroidManifest.xml',
          r'android:label="(.+?)"',
        ),
        appDisplayName,
      );
      expect(
        _one('windows/runner/Runner.rc', r'VALUE "ProductName", "(.+)" "\\0"'),
        appDisplayName,
      );
      expect(
        _one('windows/runner/main.cpp', r'window\.Create\(L"(.+?)"'),
        appDisplayName,
      );
      expect(
        _all(
          'linux/runner/my_application.cc',
          r'_set_title\(\w+, "(.+?)"\)',
        ).toSet(),
        {appDisplayName},
      );
    });
  });
}
