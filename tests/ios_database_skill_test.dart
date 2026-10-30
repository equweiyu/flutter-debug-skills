import 'dart:io';

void main() {
  final repositoryRoot = File.fromUri(Platform.script).parent.parent;
  final skillsDirectory = Directory('${repositoryRoot.path}/skills');

  _test('provides one unified iOS database inspection skill', () {
    final skillDirectory = Directory(
      '${skillsDirectory.path}/ios-database-inspection',
    );
    final skillFile = File('${skillDirectory.path}/SKILL.md');

    _expect(skillDirectory.existsSync(), 'unified iOS skill is missing');
    _expect(skillFile.existsSync(), 'unified iOS SKILL.md is missing');
    _expect(
      !File(
        '${skillsDirectory.path}/ios-simulator-database-inspection/SKILL.md',
      ).existsSync(),
      'legacy simulator-only skill still exists',
    );
    _expect(
      !File(
        '${skillsDirectory.path}/'
        'ios-physical-device-database-inspection/SKILL.md',
      ).existsSync(),
      'legacy physical-device-only skill still exists',
    );

    final content = skillFile.readAsStringSync();
    _expect(
      content.contains('name: ios-database-inspection'),
      'skill name does not match the unified directory',
    );
    _expect(
      content.contains('references/simulator.md'),
      'simulator branch is not discoverable from SKILL.md',
    );
    _expect(
      content.contains('references/physical-device.md'),
      'physical-device branch is not discoverable from SKILL.md',
    );
  });

  _test('routes both README indexes to the unified skill', () {
    const unifiedLink = 'skills/ios-database-inspection/SKILL.md';
    const legacyLinks = <String>[
      'skills/ios-simulator-database-inspection/SKILL.md',
      'skills/ios-physical-device-database-inspection/SKILL.md',
    ];

    for (final readmeName in <String>['README.md', 'README.zh-CN.md']) {
      final readme = File('${repositoryRoot.path}/$readmeName');
      _expect(readme.existsSync(), 'missing $readmeName');
      final content = readme.readAsStringSync();
      _expect(
        content.contains(']($unifiedLink)'),
        '$readmeName does not link to the unified skill',
      );
      for (final legacyLink in legacyLinks) {
        _expect(
          !content.contains(']($legacyLink)'),
          '$readmeName still links to $legacyLink',
        );
      }
    }
  });

  _test('keeps simulator and physical-device execution paths separate', () {
    final simulatorReference = File(
      '${skillsDirectory.path}/ios-database-inspection/'
      'references/simulator.md',
    );
    final physicalReference = File(
      '${skillsDirectory.path}/ios-database-inspection/'
      'references/physical-device.md',
    );

    _expect(simulatorReference.existsSync(), 'simulator reference is missing');
    _expect(
      physicalReference.existsSync(),
      'physical-device reference is missing',
    );
    _expect(
      simulatorReference.readAsStringSync().contains(
        'xcrun simctl get_app_container',
      ),
      'simulator branch does not resolve containers with simctl',
    );
    _expect(
      physicalReference.readAsStringSync().contains(
        'xcrun devicectl device copy from',
      ),
      'physical-device branch does not export with devicectl',
    );
  });

  if (exitCode != 0) {
    stderr.writeln('iOS database skill tests failed.');
  } else {
    stdout.writeln('iOS database skill tests passed.');
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
