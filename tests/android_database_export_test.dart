import 'dart:io';

Future<void> main() async {
  final repositoryRoot = File.fromUri(Platform.script).parent.parent;
  final script = File(
    '${repositoryRoot.path}/'
    'skills/android-device-database-inspection/scripts/'
    'export_android_database.sh',
  );

  await _test('exports the database and matching WAL sidecar', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'android-database-export-test.',
    );
    try {
      final fakeAdb = await _createFakeAdb(workspace);
      final output = Directory('${workspace.path}/export');
      final log = File('${workspace.path}/adb.log');

      final result = await Process.run(
        'bash',
        <String>[
          script.path,
          'test-device',
          'com.example.app',
          'databases/app.db',
          output.path,
        ],
        environment: <String, String>{
          'ADB_BIN': fakeAdb.path,
          'ADB_LOG': log.path,
        },
      );

      _expect(result.exitCode == 0, 'export failed: ${result.stderr}');
      _expect(
        _sameBytes(File('${output.path}/app.db').readAsBytesSync(), <int>[
          0,
          1,
          68,
          66,
          255,
        ]),
        'database bytes changed during export',
      );
      _expect(
        _sameBytes(File('${output.path}/app.db-wal').readAsBytesSync(), <int>[
          87,
          65,
          76,
          0,
        ]),
        'WAL bytes changed during export',
      );
      _expect(
        !File('${output.path}/app.db-shm').existsSync(),
        'missing SHM sidecar should not create a local file',
      );
      final calls = log.readAsStringSync();
      _expect(
        calls.contains(
          '-s test-device exec-out run-as com.example.app '
          'cat databases/app.db',
        ),
        'the export did not use the selected device and app package',
      );
    } finally {
      await workspace.delete(recursive: true);
    }
  });

  await _test('rejects a remote path outside the app sandbox', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'android-database-export-test.',
    );
    try {
      final fakeAdb = await _createFakeAdb(workspace);
      final log = File('${workspace.path}/adb.log');

      final result = await Process.run(
        'bash',
        <String>[
          script.path,
          'test-device',
          'com.example.app',
          '../outside.db',
          '${workspace.path}/export',
        ],
        environment: <String, String>{
          'ADB_BIN': fakeAdb.path,
          'ADB_LOG': log.path,
        },
      );

      _expect(result.exitCode != 0, 'unsafe remote path was accepted');
      _expect(
        !log.existsSync() || log.readAsStringSync().isEmpty,
        'unsafe remote path reached adb',
      );
    } finally {
      await workspace.delete(recursive: true);
    }
  });

  await _test('rejects shell syntax in a remote path', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'android-database-export-test.',
    );
    try {
      final fakeAdb = await _createFakeAdb(workspace);
      final log = File('${workspace.path}/adb.log');

      final result = await Process.run(
        'bash',
        <String>[
          script.path,
          'test-device',
          'com.example.app',
          'databases/app.db;id',
          '${workspace.path}/export',
        ],
        environment: <String, String>{
          'ADB_BIN': fakeAdb.path,
          'ADB_LOG': log.path,
        },
      );

      _expect(result.exitCode != 0, 'unsafe remote path was accepted');
      _expect(
        !log.existsSync() || log.readAsStringSync().isEmpty,
        'unsafe remote path reached adb',
      );
    } finally {
      await workspace.delete(recursive: true);
    }
  });

  await _test('refuses to overwrite an existing export', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'android-database-export-test.',
    );
    try {
      final fakeAdb = await _createFakeAdb(workspace);
      final output = Directory('${workspace.path}/export');
      await output.create();
      final existing = File('${output.path}/app.db');
      await existing.writeAsBytes(<int>[9, 9, 9]);

      final result = await Process.run(
        'bash',
        <String>[
          script.path,
          'test-device',
          'com.example.app',
          'databases/app.db',
          output.path,
        ],
        environment: <String, String>{
          'ADB_BIN': fakeAdb.path,
          'ADB_LOG': '${workspace.path}/adb.log',
        },
      );

      _expect(result.exitCode != 0, 'existing export was overwritten');
      _expect(
        _sameBytes(existing.readAsBytesSync(), <int>[9, 9, 9]),
        'existing export content was changed',
      );
    } finally {
      await workspace.delete(recursive: true);
    }
  });
}

Future<File> _createFakeAdb(Directory workspace) async {
  final fakeAdb = File('${workspace.path}/adb');
  await fakeAdb.writeAsString(r'''#!/bin/sh
set -eu
: "${ADB_LOG:?ADB_LOG is required}"
printf '%s\n' "$*" >> "$ADB_LOG"
if [ "$1" != "-s" ] || [ "$2" != "test-device" ]; then
  exit 91
fi
shift 2
if [ "$1" != "exec-out" ]; then
  exit 92
fi
shift
if [ "$1" != "run-as" ] || [ "$2" != "com.example.app" ]; then
  exit 93
fi
shift 2
case "$1" in
  test)
    case "$3" in
      databases/app.db-wal) exit 0 ;;
      databases/app.db-shm) exit 1 ;;
      *) exit 1 ;;
    esac
    ;;
  cat)
    case "$2" in
      databases/app.db) printf '\000\001DB\377' ;;
      databases/app.db-wal) printf 'WAL\000' ;;
      *) exit 94 ;;
    esac
    ;;
  *)
    exit 95
    ;;
esac
''');
  final chmod = await Process.run('chmod', <String>['+x', fakeAdb.path]);
  _expect(chmod.exitCode == 0, 'failed to make fake adb executable');
  return fakeAdb;
}

Future<void> _test(String name, Future<void> Function() body) async {
  try {
    await body();
    stdout.writeln('PASS: $name');
  } on Object catch (error) {
    stderr.writeln('FAIL: $name');
    stderr.writeln(error);
    exitCode = 1;
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
