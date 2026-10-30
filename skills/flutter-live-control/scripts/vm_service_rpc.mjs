#!/usr/bin/env node

const ALLOWED_METHODS = new Set([
  'getVM',
  'getIsolate',
  'getClassList',
  'getInstances',
  'getObject',
  'invoke',
]);

const IDENTIFIER = /^[A-Za-z_$][A-Za-z0-9_$]*$/;
const OBJECT_ID = /^(?:objects|classes|isolates)\/\S+$/;
const ISOLATE_ID = /^isolates\/\S+$/;
const CLASS_ID = /^classes\/\S+$/;

function fail(message, code = 1) {
  process.stderr.write(`vm_service_rpc: ${message}\n`);
  process.exitCode = code;
}

function usage() {
  process.stdout.write(`Usage:
  vm_service_rpc.mjs --uri <ws://127.0.0.1:.../ws> --method <method> [--params <json>] [--timeout-ms <n>]

Allowed methods:
  getVM
  getIsolate       {"isolateId":"isolates/..."}
  getClassList     {"isolateId":"isolates/..."}
  getInstances     {"isolateId":"isolates/...","objectId":"classes/...","limit":1..20}
  getObject        {"isolateId":"isolates/...","objectId":"objects/..." }
  invoke           {"isolateId":"isolates/...","targetId":"objects/...","selector":"knownMethod","argIds":[]}

Safety:
  - Connects only to 127.0.0.1 over ws:.
  - Does not implement evaluate or arbitrary methods.
  - invoke supports only zero-argument methods.
  - Never retries automatically.
`);
}

function parseArguments(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    if (key === '--help' || key === '-h') return { help: true };
    if (!['--uri', '--method', '--params', '--timeout-ms'].includes(key)) {
      throw new Error(`unknown argument: ${key}`);
    }
    const value = argv[index + 1];
    if (value == null || value.startsWith('--')) {
      throw new Error(`missing value for ${key}`);
    }
    values[key.slice(2)] = value;
    index += 1;
  }
  return values;
}

function requireString(value, name) {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`${name} must be a non-empty string`);
  }
  return value;
}

function requireIsolateId(value) {
  requireString(value, 'isolateId');
  if (!ISOLATE_ID.test(value)) {
    throw new Error('isolateId must have the form isolates/<id>');
  }
}

function requireObjectId(value, name) {
  requireString(value, name);
  if (!OBJECT_ID.test(value)) {
    throw new Error(`${name} must have the form objects/<id>, classes/<id>, or isolates/<id>`);
  }
}

function validateParams(method, rawParams) {
  const params = rawParams == null ? {} : JSON.parse(rawParams);
  if (params == null || typeof params !== 'object' || Array.isArray(params)) {
    throw new Error('--params must be a JSON object');
  }

  if (method === 'getVM') return {};
  requireIsolateId(params.isolateId);

  if (method === 'getIsolate' || method === 'getClassList') {
    return { isolateId: params.isolateId };
  }

  if (method === 'getObject') {
    requireObjectId(params.objectId, 'objectId');
    return {
      isolateId: params.isolateId,
      objectId: params.objectId,
    };
  }

  if (method === 'getInstances') {
    requireString(params.objectId, 'objectId');
    if (!CLASS_ID.test(params.objectId)) {
      throw new Error(
        'objectId must reference a class with the form classes/<id>',
      );
    }
    if (!Number.isInteger(params.limit) || params.limit < 1 || params.limit > 20) {
      throw new Error('limit must be an integer from 1 to 20');
    }
    return {
      isolateId: params.isolateId,
      objectId: params.objectId,
      limit: params.limit,
    };
  }

  requireObjectId(params.targetId, 'targetId');
  requireString(params.selector, 'selector');
  if (!IDENTIFIER.test(params.selector)) {
    throw new Error('selector must be a Dart identifier');
  }
  if (!Array.isArray(params.argIds) || params.argIds.length !== 0) {
    throw new Error('invoke is restricted to zero-argument methods');
  }
  return {
    isolateId: params.isolateId,
    targetId: params.targetId,
    selector: params.selector,
    argIds: [],
  };
}

async function run(options) {
  const url = new URL(options.uri);
  if (url.protocol !== 'ws:' || url.hostname !== '127.0.0.1') {
    throw new Error('VM Service URI must use ws://127.0.0.1');
  }

  const method = requireString(options.method, 'method');
  if (!ALLOWED_METHODS.has(method)) {
    throw new Error(`method is not allowed: ${method}`);
  }
  const params = validateParams(method, options.params);
  const timeoutMs = options['timeout-ms'] == null
    ? 5000
    : Number(options['timeout-ms']);
  if (!Number.isInteger(timeoutMs) || timeoutMs < 500 || timeoutMs > 30000) {
    throw new Error('timeout-ms must be an integer from 500 to 30000');
  }

  const socket = new WebSocket(url);
  const requestId = '1';
  let settled = false;
  const timeout = setTimeout(() => {
    if (settled) return;
    settled = true;
    fail(`request timed out after ${timeoutMs}ms`);
    socket.close();
  }, timeoutMs);

  socket.addEventListener('open', () => {
    socket.send(JSON.stringify({
      jsonrpc: '2.0',
      id: requestId,
      method,
      params,
    }));
  });

  socket.addEventListener('message', (event) => {
    if (settled) return;
    let message;
    try {
      message = JSON.parse(String(event.data));
    } catch {
      settled = true;
      clearTimeout(timeout);
      fail('received a non-JSON VM Service response');
      socket.close();
      return;
    }
    if (message.id !== requestId) return;

    settled = true;
    clearTimeout(timeout);
    if (message.error != null) {
      process.stdout.write(`${JSON.stringify({ error: message.error }, null, 2)}\n`);
      process.exitCode = 1;
    } else {
      process.stdout.write(`${JSON.stringify(message.result, null, 2)}\n`);
    }
    socket.close();
  });

  socket.addEventListener('error', () => {
    if (settled) return;
    settled = true;
    clearTimeout(timeout);
    fail('VM Service connection failed');
  });

  socket.addEventListener('close', () => {
    if (settled) return;
    settled = true;
    clearTimeout(timeout);
    fail('VM Service connection closed before a response');
  });
}

try {
  const options = parseArguments(process.argv.slice(2));
  if (options.help) {
    usage();
  } else {
    await run(options);
  }
} catch (error) {
  fail(error instanceof Error ? error.message : String(error), 64);
}
