import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final repositoryRoot = File.fromUri(Platform.script).parent.parent;
  final script = File(
    '${repositoryRoot.path}/'
    'skills/flutter-live-control/scripts/vm_service_rpc.mjs',
  );

  await _test('getInstances sends objectId to VM Service', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    final requestCompleter = Completer<Map<String, dynamic>>();

    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((message) {
        final decoded = jsonDecode(message as String) as Map<String, dynamic>;
        if (decoded['method'] != 'getInstances') return;
        requestCompleter.complete(decoded);
        socket.add(
          jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': decoded['id'],
            'result': <String, Object?>{
              'type': 'InstanceSet',
              'totalCount': 1,
              'instances': <Object?>[],
            },
          }),
        );
      });
    });

    try {
      final result = await Process.run('node', <String>[
        script.path,
        '--uri',
        'ws://127.0.0.1:${server.port}/LOCAL_TEST_TOKEN/ws',
        '--method',
        'getInstances',
        '--params',
        '{"isolateId":"isolates/test",'
            '"objectId":"classes/4298","limit":1}',
      ]);
      _expect(
        result.exitCode == 0,
        'VM Service helper failed: ${result.stderr}',
      );

      final request = await requestCompleter.future.timeout(
        const Duration(seconds: 2),
      );
      final params = request['params'] as Map<String, dynamic>;
      _expect(
        params['objectId'] == 'classes/4298',
        'objectId was not forwarded',
      );
      _expect(
        !params.containsKey('classId'),
        'classId must not be sent to VM Service',
      );
      _expect(params['limit'] == 1, 'limit was not forwarded as an integer');
    } finally {
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    }
  });
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
