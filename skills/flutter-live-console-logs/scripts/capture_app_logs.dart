// 只读诊断：仅连接本机 127.0.0.1，订阅 Logging 流并把日志写到 stdout。
// 用法：dart capture_app_logs.dart --uri <ws-url> [--name <regex>] [--seconds <n>] [--verbose]
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    _Options._printUsage();
    return;
  }
  final options = _Options.parse(arguments);
  if (options == null) {
    exitCode = 64;
    return;
  }

  try {
    await _capture(options);
  } on Object catch (error, stackTrace) {
    _reportError('capture failed', error, stackTrace, options);
    exitCode = 1;
  }
}

Future<void> _capture(_Options options) async {
  final socket = await WebSocket.connect(
    options.uri.toString(),
  ).timeout(const Duration(seconds: 10));
  final client = _LogClient(socket, options);
  final stop = Completer<void>();
  final signalSubscriptions = <StreamSubscription<ProcessSignal>>[];
  Timer? timer;

  void requestStop() {
    if (!stop.isCompleted) stop.complete();
  }

  for (final signal in <ProcessSignal>[
    ProcessSignal.sigint,
    ProcessSignal.sigterm,
  ]) {
    try {
      signalSubscriptions.add(signal.watch().listen((_) => requestStop()));
    } on UnsupportedError {
      // 当前平台不支持该信号；其余停止方式仍然可用。
    }
  }

  final seconds = options.seconds;
  if (seconds != null) {
    timer = Timer(Duration(seconds: seconds), requestStop);
  }

  unawaited(
    socket.done.then(
      (_) {
        if (!stop.isCompleted) {
          stderr.writeln('capture_app_logs: VM Service connection closed');
          exitCode = 1;
          requestStop();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _reportError(
          'VM Service connection failed',
          error,
          stackTrace,
          options,
        );
        exitCode = 1;
        requestStop();
      },
    ),
  );

  try {
    await client.start();
    stderr.writeln('connected: ${options.uri.host}:${options.uri.port}');
    await stderr.flush();
    await stop.future;
  } finally {
    timer?.cancel();
    for (final subscription in signalSubscriptions) {
      await subscription.cancel();
    }
    await client.stop();
  }
}

class _LogClient {
  _LogClient(this._socket, this._options);

  static const Duration _requestTimeout = Duration(seconds: 10);

  final WebSocket _socket;
  final _Options _options;
  final Map<int, Completer<Map<String, dynamic>>> _pending =
      <int, Completer<Map<String, dynamic>>>{};
  StreamSubscription<dynamic>? _subscription;
  Future<void> _writeQueue = Future<void>.value();
  int _nextRequestId = 1;

  Future<void> start() async {
    _subscription = _socket.listen(
      _handleMessage,
      onError: (Object error, StackTrace stackTrace) {
        _reportError('socket error', error, stackTrace, _options);
      },
    );
    final response = await _request('streamListen', <String, Object?>{
      'streamId': 'Logging',
    });
    final error = response['error'];
    if (error != null) {
      throw StateError('streamListen failed: $error');
    }
  }

  Future<void> stop() async {
    await _writeQueue;
    await _subscription?.cancel();
    await _socket.close(WebSocketStatus.normalClosure);
  }

  void _handleMessage(dynamic message) {
    final Map<String, dynamic> decoded;
    try {
      final text = message is String
          ? message
          : utf8.decode(message as List<int>);
      final value = jsonDecode(text);
      if (value is! Map<String, dynamic>) return;
      decoded = value;
    } on Object catch (error, stackTrace) {
      _reportError('invalid VM Service message', error, stackTrace, _options);
      return;
    }

    final requestId = decoded['id'];
    if (requestId is int && !decoded.containsKey('method')) {
      final completer = _pending.remove(requestId);
      completer?.complete(decoded);
      return;
    }

    final params = decoded['params'];
    if (params is! Map<String, dynamic>) return;
    final event = params['event'];
    if (event is! Map<String, dynamic> || event['kind'] != 'Logging') {
      return;
    }

    final eventCopy = Map<String, dynamic>.from(event);
    _writeQueue = _writeQueue.then((_) async {
      try {
        await _writeLog(eventCopy);
      } on Object catch (error, stackTrace) {
        _reportError('failed to read log', error, stackTrace, _options);
      }
    });
  }

  Future<void> _writeLog(Map<String, dynamic> event) async {
    final record = event['logRecord'];
    if (record is! Map<String, dynamic>) return;

    final isolate = event['isolate'];
    final isolateId = isolate is Map<String, dynamic>
        ? isolate['id'] as String?
        : null;
    final loggerName = await _readString(record['loggerName'], isolateId);
    final pattern = _options.namePattern;
    if (pattern != null && !pattern.hasMatch(loggerName)) return;

    final message = await _readString(record['message'], isolateId);
    final level = record['level'];
    final time = record['time'];
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      time is int ? time : DateTime.now().millisecondsSinceEpoch,
    );
    stdout.writeln(
      '${_formatTimestamp(timestamp)} level=${level is int ? level : -1} '
      'name=$loggerName $message',
    );
    await stdout.flush();
  }

  Future<String> _readString(Object? raw, String? isolateId) async {
    if (raw == null) return '';
    if (raw is String) return raw;
    if (raw is! Map<String, dynamic>) return raw.toString();

    final inlineValue = raw['valueAsString'];
    final inlineText = inlineValue is String ? inlineValue : '';
    if (raw['valueAsStringIsTruncated'] != true || isolateId == null) {
      return inlineText;
    }

    final objectId = raw['id'];
    final length = raw['length'];
    if (objectId is! String || length is! int || length <= 0) {
      return inlineText;
    }

    final buffer = StringBuffer();
    var offset = 0;
    while (offset < length) {
      final remaining = length - offset;
      final response = await _request('getObject', <String, Object?>{
        'isolateId': isolateId,
        'objectId': objectId,
        'offset': offset,
        'count': remaining,
      });
      if (response['error'] != null) break;
      final result = response['result'];
      if (result is! Map<String, dynamic>) break;
      final chunk = result['valueAsString'];
      if (chunk is! String || chunk.isEmpty) break;
      buffer.write(chunk);
      offset += chunk.length;
      if (chunk.length >= remaining) break;
    }
    return buffer.isEmpty ? inlineText : buffer.toString();
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, Object?> params,
  ) {
    final requestId = _nextRequestId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[requestId] = completer;
    _socket.add(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': requestId,
        'method': method,
        'params': params,
      }),
    );
    return completer.future.timeout(
      _requestTimeout,
      onTimeout: () {
        _pending.remove(requestId);
        throw TimeoutException('VM Service request timed out: $method');
      },
    );
  }
}

class _Options {
  const _Options({
    required this.uri,
    required this.namePattern,
    required this.seconds,
    required this.verbose,
  });

  final Uri uri;
  final RegExp? namePattern;
  final int? seconds;
  final bool verbose;

  static _Options? parse(List<String> arguments) {
    String? uri;
    String? name;
    int? seconds;
    var verbose = false;

    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument == '--verbose' || argument == '-v') {
        verbose = true;
        continue;
      }
      if (argument == '--uri' ||
          argument == '--name' ||
          argument == '--seconds') {
        if (index + 1 >= arguments.length) {
          _printUsage('缺少 $argument 的值');
          return null;
        }
        final value = arguments[++index];
        switch (argument) {
          case '--uri':
            uri = value;
          case '--name':
            name = value;
          case '--seconds':
            seconds = int.tryParse(value);
            if (seconds == null || seconds <= 0) {
              _printUsage('--seconds 必须是正整数');
              return null;
            }
        }
        continue;
      }
      if (argument.startsWith('-') || uri != null) {
        _printUsage('无法识别参数：$argument');
        return null;
      }
      uri = argument;
    }

    final parsedUri = uri == null ? null : Uri.tryParse(uri);
    if (parsedUri == null ||
        parsedUri.scheme != 'ws' ||
        parsedUri.host != '127.0.0.1' ||
        !parsedUri.hasPort ||
        parsedUri.userInfo.isNotEmpty) {
      _printUsage('--uri 必须是带端口的本机 ws://127.0.0.1:<port>/... 地址');
      return null;
    }

    RegExp? pattern;
    if (name != null) {
      try {
        pattern = RegExp(name);
      } on FormatException {
        _printUsage('--name 不是合法正则表达式');
        return null;
      }
    }

    return _Options(
      uri: parsedUri,
      namePattern: pattern,
      seconds: seconds,
      verbose: verbose,
    );
  }

  static void _printUsage([String? error]) {
    if (error != null) stderr.writeln(error);
    stderr.writeln(
      'Usage: dart capture_app_logs.dart '
      '--uri ws://127.0.0.1:<port>/<token>/ws '
      '[--name <regex>] [--seconds <n>] [--verbose]',
    );
  }
}

void _reportError(
  String context,
  Object error,
  StackTrace stackTrace,
  _Options options,
) {
  stderr.writeln(
    'capture_app_logs: $context: '
    '${_redactSensitiveText(error.toString(), options.uri)}',
  );
  if (!options.verbose) return;

  var formattedStack = _redactSensitiveText(stackTrace.toString(), options.uri);
  final homePaths = <String?>{
    Platform.environment['HOME'],
    Platform.environment['USERPROFILE'],
  }.whereType<String>().where((path) => path.isNotEmpty);
  for (final homePath in homePaths) {
    formattedStack = formattedStack.replaceAll(homePath, '~');
  }
  if (formattedStack.isNotEmpty) stderr.writeln(formattedStack);
}

String _redactSensitiveText(String text, Uri uri) {
  var redacted = text.replaceAll(
    uri.toString(),
    'ws://${uri.host}:${uri.port}',
  );
  if (uri.path.isNotEmpty && uri.path != '/') {
    redacted = redacted.replaceAll(uri.path, '/<redacted>');
  }
  if (uri.query.isNotEmpty) {
    redacted = redacted.replaceAll(uri.query, '<redacted>');
  }
  if (uri.fragment.isNotEmpty) {
    redacted = redacted.replaceAll(uri.fragment, '<redacted>');
  }
  return redacted;
}

String _formatTimestamp(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  final milliseconds = value.millisecond.toString().padLeft(3, '0');
  return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}:'
      '${twoDigits(value.second)}.$milliseconds';
}
