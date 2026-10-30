---
name: flutter-live-console-logs
description: Capture and inspect Flutter/Dart console logs through DTD and the VM Service Logging stream, including buffered history and live events. Use for 控制台日志、console history、runtime diagnostics、timing investigations, or when terminal scrollback is unavailable.
metadata:
  short-description: Capture and replay Flutter app logs via VM Service
---

# Flutter 控制台日志采集与回放

通过 DTD 找到正在运行的 Flutter App，订阅 VM Service 的 `Logging` 流并把完整日志写入文件。默认按 logger 名称过滤；未指定时输出全部 `developer.log` 事件。先尝试读取缓冲区历史；需要确定性的新复现时，再启动持续采集。

## 能力边界

- 当前 Flutter VM Service 在订阅 `Logging` 时会先回放缓冲区记录，可能包含 App 启动以来的日志；但这不属于稳定完整性保证，缓冲区上限、热重启和连接时机都可能造成缺口。
- 如果历史日志没有覆盖目标操作，启动采集后让用户在同一个 App 实例上重新操作。Hot restart 后先重新确认 VM Service URI；请求 ID、session ID 和序号可能重新计数，不能把不同时间段的同名标识合并。
- `get_runtime_errors` 只返回运行时异常，不包含应用通过 `developer.log` 输出的普通日志，不能替代日志采集。
- 日志可能包含用户数据；先用 logger 名称缩小范围，不记录或转贴凭据、token、密码、密钥材料、签名载荷等敏感内容。

## 获取 VM Service URI

1. 调用 Dart MCP 的 `dtd listDtdUris`。
2. 选择 `Workspace Root` 与当前仓库一致的 DTD，调用 `dtd connect`。
3. 调用 `dtd listConnectedApps`，选择目标 App 的 `uri`。该值通常形如：

   ```text
   ws://127.0.0.1:50897/mlH4IUsr9qU=/ws
   ```

   不要使用 DTD 自身的 `ws://.../token=`，也不要把 App URI 末尾的 `/ws` 去掉。

如果 DTD 不可用，可从 `flutter attach` 输出找到 `http://127.0.0.1:<PORT>/<TOKEN>=`，转换成 `ws://127.0.0.1:<PORT>/<TOKEN>=/ws`。有多个 App 时先确认设备、包名和当前仓库，不要猜测。

## 读取历史缓冲区

先用 3 秒采集尝试取出已缓冲的日志；连接后记录会快速回放，3 秒通常足够：

```bash
VM_SERVICE_WS_URI='<粘贴 dtd listConnectedApps 返回的 App uri>'
umask 077
LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/flutter-console-logs.XXXXXX")"
chmod 700 "$LOG_DIR"
LOG="$LOG_DIR/history-$(date +%Y%m%d-%H%M%S).log"
LOGGER_PATTERN='<logger regex>'

dart .agents/skills/flutter-live-console-logs/scripts/capture_app_logs.dart \
  --uri "$VM_SERVICE_WS_URI" \
  --name "$LOGGER_PATTERN" \
  --seconds 3 \
  >"$LOG" 2>"$LOG.stderr"

wc -l "$LOG"
head -3 "$LOG"
tail -3 "$LOG"
printf 'history log: %s\n' "$LOG"
```

如果目标时间段已在日志中，直接分析，不必让用户重新操作。如果日志为空、截止时间早于目标操作，或 App 刚刚重启，再进入持续采集。

可用请求 ID、session ID、logger 名称或已知事件文本定位目标时间段，只读取附近上下文：

```bash
rg -n '<search pattern>|session=|request_id=' "$LOG" | tail -100
```

## 启动持续采集

在仓库根目录执行。后台运行时把 stdout 写日志文件、stderr 写连接状态，并保存 PID。`latest.*` 是当前采集的稳定入口，便于后续命令在不同 shell 中读取。同一时间只保留一个持续采集，新的采集会覆盖 `latest.*`：

```bash
VM_SERVICE_WS_URI='<粘贴 dtd listConnectedApps 返回的 App uri>'
umask 077
LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/flutter-console-logs.XXXXXX")"
chmod 700 "$LOG_DIR"
LOG="$LOG_DIR/app-$(date +%Y%m%d-%H%M%S).log"
LOGGER_PATTERN='<logger regex>'

nohup dart .agents/skills/flutter-live-console-logs/scripts/capture_app_logs.dart \
  --uri "$VM_SERVICE_WS_URI" \
  --name "$LOGGER_PATTERN" \
  --seconds 1800 \
  >"$LOG" 2>"$LOG.stderr" &
echo $! >"$LOG_DIR/latest.pid"
ln -sfn "$LOG" "$LOG_DIR/latest.log"
ln -sfn "$LOG.stderr" "$LOG_DIR/latest.stderr"
printf 'capture log: %s\n' "$LOG"
printf 'log directory: %s\n' "$LOG_DIR"
```

连接确认：

```bash
sleep 1
cat "$LOG_DIR/latest.stderr"
ps -p "$(cat "$LOG_DIR/latest.pid")" -o pid=,etime=,command=
```

等待状态中出现 `connected`，再请用户复现。若只需前台观察，可去掉 `--seconds`、`nohup` 和重定向，使用 `Ctrl-C` 结束。

脚本参数：

- `--uri <ws-url>`：必填，App 的 VM Service WebSocket URI。
- `--name <regex>`：可选，按 `loggerName` 过滤；可用 `A|B` 匹配多个 logger。
- `--seconds <n>`：可选，至少采集 n 秒；历史积压较多时会把队列写完后再退出。不传则持续到 `Ctrl-C` 或 `SIGTERM`。
- `--verbose`：错误时额外输出堆栈。默认只显示经过清理的错误摘要，URI token 和用户目录不会写入 stderr。

## 复现与读取

先按历史回放判断是否需要用户复现。需要新日志时按以下步骤执行：

1. 告诉用户“日志采集已启动，请现在重新操作一次刚才的页面或流程”。
2. 用户确认后读取日志文件，先看首尾和关键事件，不要一次输出整份日志：

   ```bash
   LOG_DIR='<上文输出的日志目录>'
   rg -n 'event=(start|end|error|timeout)|request_id=|session=' \
     "$LOG_DIR/latest.log" | tail -100
   ```

3. 如需核对异常，再调用 Dart MCP 的 `get_runtime_errors`。它和日志文件是两种证据，不要混写。
4. 日志事件名称因项目而异。优先按 request/session 标识关联相邻事件，再结合时间戳和行号计算耗时。
   - `start -> end` 类事件可表示加载或请求耗时，但需结合具体 logger 确认。
   - `error`、`timeout` 和状态变更事件应与正常完成事件分开判断。
   - session 结束只表示会话边界，不能单独证明业务操作成功或页面加载完成。
   - 不要在未确认事件语义时，仅凭字段名推断缓存、网络或业务状态。

## 结束采集

分析完成后停止后台进程，保留日志路径供用户复查：

```bash
LOG_DIR='<上文输出的日志目录>'
if [ -f "$LOG_DIR/latest.pid" ]; then
  PID="$(cat "$LOG_DIR/latest.pid")"
  kill "$PID" 2>/dev/null || true
  for _ in {1..25}; do
    kill -0 "$PID" 2>/dev/null || break
    sleep 0.2
  done
  if kill -0 "$PID" 2>/dev/null; then
    kill -9 "$PID" 2>/dev/null || true
  fi
  rm -f "$LOG_DIR/latest.pid"
fi
```

历史回放可能一次产生数千行，直接结束进程通常需要几秒把写入队列排空；上面的命令最多等待 5 秒再强制结束。不要在读取前删除日志。最后报告日志文件路径、采集时间范围、目标 logger，以及依据日志得出的结论；明确区分“日志未覆盖”与“没有发生”。
