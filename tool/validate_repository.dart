import 'dart:io';

const readmePaths = <String>['README.md', 'README.zh-CN.md'];

void main() {
  final repositoryRoot = File.fromUri(Platform.script).parent.parent;
  final failures = <String>[];
  final skillDirectories = _skillDirectories(repositoryRoot);

  if (!File('${repositoryRoot.path}/LICENSE').existsSync()) {
    failures.add('Missing LICENSE.');
  }
  if (skillDirectories.isEmpty) {
    failures.add('No skill directories found under skills/.');
  }

  for (final directory in skillDirectories) {
    _validateSkill(directory, failures);
  }
  _validateReadmes(repositoryRoot, skillDirectories, failures);

  if (failures.isNotEmpty) {
    stderr.writeln('Repository validation failed:');
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Repository validation passed: '
    '${skillDirectories.length} skills.',
  );
}

List<Directory> _skillDirectories(Directory root) {
  final skills = Directory('${root.path}/skills');
  if (!skills.existsSync()) return <Directory>[];
  return skills
      .listSync()
      .whereType<Directory>()
      .where((directory) => !directory.path.split('/').last.startsWith('.'))
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));
}

void _validateSkill(Directory directory, List<String> failures) {
  final skillName = directory.path.split('/').last;
  final skillFile = File('${directory.path}/SKILL.md');
  if (!skillFile.existsSync()) {
    failures.add('$skillName: missing SKILL.md.');
    return;
  }

  final frontmatter = _frontmatter(skillFile.readAsStringSync());
  if (frontmatter == null) {
    failures.add('$skillName: missing YAML frontmatter.');
    return;
  }

  final nameMatch = RegExp(
    r'^name:\s*(\S+)\s*$',
    multiLine: true,
  ).firstMatch(frontmatter);
  if (nameMatch?.group(1) != skillName) {
    failures.add('$skillName: frontmatter name must match its directory.');
  }
  if (!RegExp(r'^description:\s*\S', multiLine: true).hasMatch(frontmatter)) {
    failures.add('$skillName: missing description.');
  }
  if (!RegExp(
    r'^\s{2}short-description:\s*\S',
    multiLine: true,
  ).hasMatch(frontmatter)) {
    failures.add('$skillName: missing metadata.short-description.');
  }

  final agentConfig = File('${directory.path}/agents/openai.yaml');
  if (!agentConfig.existsSync()) {
    failures.add('$skillName: missing agents/openai.yaml.');
    return;
  }
  final interface = agentConfig.readAsStringSync();
  if (!RegExp(
    r'^\s{2}display_name:\s*\S',
    multiLine: true,
  ).hasMatch(interface)) {
    failures.add('$skillName: missing interface.display_name.');
  }
  if (!RegExp(
    r'^\s{2}short_description:\s*\S',
    multiLine: true,
  ).hasMatch(interface)) {
    failures.add('$skillName: missing interface.short_description.');
  }
}

void _validateReadmes(
  Directory root,
  List<Directory> skillDirectories,
  List<String> failures,
) {
  final expectedLinks = skillDirectories
      .map((directory) => 'skills/${directory.path.split('/').last}/SKILL.md')
      .toList();
  List<String>? englishLinks;

  for (final readmePath in readmePaths) {
    final readme = File('${root.path}/$readmePath');
    if (!readme.existsSync()) {
      failures.add('Missing $readmePath.');
      continue;
    }

    final content = readme.readAsStringSync();
    final links = RegExp(
      r'\]\((skills/[^)#]+/SKILL\.md)\)',
    ).allMatches(content).map((match) => match.group(1)!).toList();
    final relativeLinks = RegExp(
      r'\]\((?!https?://|#)([^)]+)\)',
    ).allMatches(content).map((match) => match.group(1)!).toList();

    if (!_sameSet(links, expectedLinks)) {
      failures.add(
        '$readmePath: skill links do not match the skills directory.',
      );
    }
    if (links.toSet().length != links.length) {
      failures.add('$readmePath: duplicate skill links.');
    }
    for (final link in links) {
      if (!File('${root.path}/$link').existsSync()) {
        failures.add('$readmePath: broken skill link $link.');
      }
    }
    for (final link in relativeLinks) {
      final target = link.split('#').first;
      if (!File('${root.path}/$target').existsSync() &&
          !Directory('${root.path}/$target').existsSync()) {
        failures.add('$readmePath: broken relative link $link.');
      }
    }
    if (!content.contains('](LICENSE)')) {
      failures.add('$readmePath: missing MIT License link.');
    }

    if (readmePath == 'README.md') {
      englishLinks = links;
      if (!content.contains('README.zh-CN.md')) {
        failures.add('README.md: missing Chinese language link.');
      }
    } else {
      if (!content.contains('README.md')) {
        failures.add('README.zh-CN.md: missing English language link.');
      }
      if (englishLinks != null && !_sameItems(links, englishLinks)) {
        failures.add('README language versions contain different skill links.');
      }
    }
  }
}

String? _frontmatter(String content) {
  final normalized = content.replaceAll('\r\n', '\n');
  if (!normalized.startsWith('---\n')) return null;
  final end = normalized.indexOf('\n---', 4);
  if (end < 0) return null;
  return normalized.substring(4, end);
}

bool _sameItems(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameSet(List<String> left, List<String> right) {
  final leftSet = left.toSet();
  final rightSet = right.toSet();
  return leftSet.length == rightSet.length && leftSet.containsAll(rightSet);
}
