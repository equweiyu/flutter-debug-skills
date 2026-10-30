import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final repositoryRoot = File.fromUri(Platform.script).parent.parent;
  final script = File(
    '${repositoryRoot.path}/'
    'skills/flutter-live-console-logs/scripts/capture_app_logs.dart',
  );
  final dart = Platform.resolvedExecutable;

  await _test('rejects non-ws WebSocket schemes', () async {
    final result = await Process.run(dart, <String>[
      script.path,
      '--uri',
      'wss://127.0.0.1:1/SECRET_TOKEN/ws',
      '--seconds',
      '1',
    ]);
    _expect(
      result.exitCode == 64,
      'expected usage error, got ${result.exitCode}',
    );
    _expect(
      '${result.stderr}'.contains('ws://127.0.0.1'),
      'expected a local ws:// validation error',
    );
  });

  await _test('rejects non-allowlisted WebSocket hosts', () async {
    final result = await Process.run(dart, <String>[
      script.path,
      '--uri',
      'ws://localhost:1/SECRET_TOKEN/ws',
      '--seconds',
      '1',
    ]);
    _expect(
      result.exitCode == 64,
      'expected usage error, got ${result.exitCode}',
    );
    _expect(
      '${result.stderr}'.contains('ws://127.0.0.1'),
      'expected a local ws:// validation error',
    );
  });

  await _test('redacts errors from failed connections', () async {
    const token = 'FAILED_CONNECTION_TOKEN';
    final result = await Process.run(dart, <String>[
      script.path,
      '--uri',
      'ws://127.0.0.1:1/$token/ws',
      '--seconds',
      '1',
    ]);
    _expect(
      result.exitCode == 1,
      'expected connection error, got ${result.exitCode}',
    );
    _expect(
      '${result.stderr}'.contains('capture failed'),
      'expected a concise capture error',
    );
    _expect(
      !'${result.stderr}'.contains(token),
      'stderr exposed the VM Service token',
    );
    _expect(
      !'${result.stderr}'.contains('#0'),
      'stderr exposed a raw stack trace',
    );
  });

  await _test('verbose errors redact token and home path', () async {
    const token = 'VERBOSE_CONNECTION_TOKEN';
    final home = Platform.environment['HOME'];
    final result = await Process.run(dart, <String>[
      script.path,
      '--uri',
      'ws://127.0.0.1:1/$token/ws',
      '--seconds',
      '1',
      '--verbose',
    ]);
    _expect(
      result.exitCode == 1,
      'expected connection error, got ${result.exitCode}',
    );
    _expect(
      '${result.stderr}'.contains('#0'),
      'verbose mode did not include the stack trace',
    );
    _expect(
      !'${result.stderr}'.contains(token),
      'verbose stderr exposed the VM Service token',
    );
    if (home != null && home.isNotEmpty) {
      _expect(
        !'${result.stderr}'.contains(home),
        'verbose stderr exposed the home directory',
      );
    }
  });

  await _test(
    'captures filtered logging events without exposing token',
    () async {
      const token = 'LOCAL_TEST_TOKEN';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((message) {
          final decoded = jsonDecode(message as String) as Map<String, dynamic>;
          if (decoded['method'] == 'streamListen') {
            socket.add(
              jsonEncode(<String, Object?>{
                'jsonrpc': '2.0',
                'id': decoded['id'],
                'result': <String, Object?>{},
              }),
            );
            socket.add(_loggingEvent('MatchLogger', 'included-log-event'));
            socket.add(_loggingEvent('OtherLogger', 'excluded-log-event'));
          }
        });
      });

      try {
        final uri = 'ws://127.0.0.1:${server.port}/$token/ws';
        final result = await Process.run(dart, <String>[
          script.path,
          '--uri',
          uri,
          '--name',
          'MatchLogger',
          '--seconds',
          '1',
        ]);
        _expect(result.exitCode == 0, 'capture failed: ${result.stderr}');
        _expect(
          '${result.stderr}'.contains('connected: 127.0.0.1:${server.port}'),
          'expected a redacted endpoint message',
        );
        _expect(
          !'${result.stderr}'.contains(token),
          'stderr exposed the VM Service token',
        );
        _expect(
          '${result.stdout}'.contains('included-log-event'),
          'matching log event was not captured',
        );
        _expect(
          !'${result.stdout}'.contains('excluded-log-event'),
          'logger filter did not exclude the non-matching event',
        );
      } finally {
        for (final socket in sockets) {
          await socket.close();
        }
        await server.close(force: true);
      }
    },
  );
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

String _loggingEvent(String loggerName, String message) {
  return jsonEncode(<String, Object?>{
    'jsonrpc': '2.0',
    'method': 'streamNotify',
    'params': <String, Object?>{
      'event': <String, Object?>{
        'kind': 'Logging',
        'isolate': <String, Object?>{'id': 'isolates/test'},
        'logRecord': <String, Object?>{
          'loggerName': loggerName,
          'message': message,
          'level': 800,
          'time': DateTime.now().millisecondsSinceEpoch,
        },
      },
    },
  });
}
