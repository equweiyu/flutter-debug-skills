import 'dart:io';

void main() {
  final repositoryRoot = File.fromUri(Platform.script).parent.parent;
  final skillsDirectory = Directory('${repositoryRoot.path}/skills');

  _test('guards iOS Simulator database mutation', () {
    final skillFile = File(
      '${skillsDirectory.path}/ios-database-inspection/SKILL.md',
    );
    final mutationReference = File(
      '${skillsDirectory.path}/ios-database-inspection/'
      'references/simulator-mutation.md',
    );
    final physicalReference = File(
      '${skillsDirectory.path}/ios-database-inspection/'
      'references/physical-device.md',
    );

    _expectSkillFile(skillFile);
    final skill = skillFile.readAsStringSync();
    _expect(
      skill.contains('默认只读'),
      'iOS skill does not make read-only the default',
    );
    _expect(
      skill.contains('references/simulator-mutation.md'),
      'iOS Simulator mutation flow is not discoverable',
    );
    _expect(
      mutationReference.existsSync(),
      'iOS Simulator mutation reference is missing',
    );

    final mutation = mutationReference.readAsStringSync();
    _expectMentioned(mutation, <String>[
      '显式',
      '确认',
      'xcrun simctl terminate',
      '.backup',
      'BEGIN IMMEDIATE',
      'PRAGMA quick_check',
      '.restore',
    ], 'iOS Simulator mutation flow');
    _expect(
      !mutation.contains(r'sqlite3 -readonly "$DATABASE_PATH" ".restore'),
      'iOS restore command must not open the database read-only',
    );

    final physical = physicalReference.readAsStringSync();
    _expect(
      physical.contains('不提供') && physical.contains('写回'),
      'physical-device reference must keep writes unsupported',
    );
  });

  _test('guards Android database mutation', () {
    final skillFile = File(
      '${skillsDirectory.path}/android-device-database-inspection/SKILL.md',
    );
    final mutationReference = File(
      '${skillsDirectory.path}/android-device-database-inspection/'
      'references/mutation.md',
    );

    _expectSkillFile(skillFile);
    final skill = skillFile.readAsStringSync();
    _expect(
      skill.contains('默认只读'),
      'Android skill does not make read-only the default',
    );
    _expect(
      skill.contains('references/mutation.md'),
      'Android mutation flow is not discoverable',
    );
    _expect(
      mutationReference.existsSync(),
      'Android mutation reference is missing',
    );

    final mutation = mutationReference.readAsStringSync();
    _expectMentioned(mutation, <String>[
      '显式',
      '确认',
      'am force-stop',
      '-journal',
      '.backup',
      'BEGIN IMMEDIATE',
      'PRAGMA quick_check',
      'exec-in',
      '恢复',
    ], 'Android mutation flow');
  });

  _test('orders mutation steps to avoid stale snapshots and overwrites', () {
    final androidMutation = File(
      '${skillsDirectory.path}/android-device-database-inspection/'
      'references/mutation.md',
    ).readAsStringSync();
    final forceStop = androidMutation.indexOf('am force-stop');
    final finalExport = androidMutation.indexOf(
      r'EXPORT_DIR="$(mktemp -d '
      r'"${TMPDIR:-/tmp}/android-database-mutation',
    );
    final stagingDirectory = androidMutation.indexOf(
      r'mkdir "$REMOTE_WORK_DIR"',
    );
    final stagingTransfer = androidMutation.indexOf('exec-in run-as');

    _expect(forceStop >= 0, 'Android mutation does not stop the app');
    _expect(
      finalExport > forceStop,
      'Android final export must happen after force-stop',
    );
    _expect(
      stagingDirectory >= 0 && stagingDirectory < stagingTransfer,
      'Android must reserve a unique staging directory before transfer',
    );

    final iosMutation = File(
      '${skillsDirectory.path}/ios-database-inspection/'
      'references/simulator-mutation.md',
    ).readAsStringSync();
    final terminate = iosMutation.indexOf('xcrun simctl terminate');
    final backup = iosMutation.indexOf(r'''".backup '$BACKUP'"''');
    final restore = iosMutation.indexOf(r'''".restore '$BACKUP'"''');

    _expect(terminate >= 0, 'iOS mutation does not stop the app');
    _expect(backup > terminate, 'iOS backup must happen after termination');
    _expect(restore > backup, 'iOS restore must use the completed backup');
  });

  if (exitCode != 0) {
    stderr.writeln('Database mutation policy tests failed.');
  } else {
    stdout.writeln('Database mutation policy tests passed.');
  }
}

void _expectSkillFile(File file) {
  _expect(file.existsSync(), '${file.path} is missing');
}

void _expectMentioned(
  String content,
  List<String> requiredPhrases,
  String workflow,
) {
  for (final phrase in requiredPhrases) {
    _expect(content.contains(phrase), '$workflow does not mention $phrase');
  }
}

void _test(String name, void Function() body) {
  try {
    body();
    stdout.writeln('PASS: $name');
  } on Object catch (error) {
    stderr.writeln('FAIL: $name: $error');
    exitCode = 1;
  }
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
