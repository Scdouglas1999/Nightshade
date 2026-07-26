const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

function createClient(overrides) {
  const apiPath = path.join(__dirname, '..', 'js', 'api.js');
  const source = fs.readFileSync(apiPath, 'utf8');
  const sandbox = {
    AbortController,
    Map,
    Set,
    URLSearchParams,
    clearInterval,
    clearTimeout,
    console,
    ...(overrides || {}),
    setInterval,
    setTimeout,
  };
  vm.createContext(sandbox);
  vm.runInContext(`${source}\nthis.TestApi = NightshadeApi;`, sandbox);
  return new sandbox.TestApi();
}

test('dome sync sends the host enable key for both toggle states', async () => {
  const client = createClient();
  const requests = [];
  client._post = async (requestPath, body) => {
    requests.push({ requestPath, body });
    return {};
  };

  await client.domeSyncToMount('dome-1', true);
  await client.domeSyncToMount('dome-1', false);

  // Bodies originate in the VM context, so normalize away cross-realm object
  // prototypes before structural comparison.
  assert.deepEqual(JSON.parse(JSON.stringify(requests)), [
    {
      requestPath: '/api/dome/sync',
      body: { deviceId: 'dome-1', enable: true },
    },
    {
      requestPath: '/api/dome/sync',
      body: { deviceId: 'dome-1', enable: false },
    },
  ]);
});

test('saved sequence load-and-start stays server-side and uses a numeric id', async () => {
  const client = createClient();
  const requests = [];
  client._get = async () => {
    throw new Error('load-and-start must not synthesize native JSON in JS');
  };
  client._post = async (requestPath, body) => {
    requests.push({ requestPath, body });
    return { status: 'started' };
  };

  await client.sequencerLoadAndStart('42');

  assert.deepEqual(JSON.parse(JSON.stringify(requests)), [
    {
      requestPath: '/api/sequencer/load-and-start',
      body: { sequenceId: 42 },
    },
  ]);
  await assert.rejects(
    client.sequencerLoadAndStart('not-a-number'),
    /Invalid sequence id/,
  );
});

test('bearer gallery media uses authenticated blob requests, never URL tokens', async () => {
  const fetches = [];
  const client = createClient({
    fetch: async (url, options) => {
      fetches.push({ url, options });
      return {
        ok: true,
        status: 200,
        headers: { get: () => '' },
        blob: async () => ({}),
        text: async () => '',
      };
    },
  });
  client.configure('http://nightshade.local:8080', 'secret-token', 'browser-1');

  assert.equal(client.usesHeaderAuth, true);
  assert.equal(
    client.imageDownloadUrl(7),
    'http://nightshade.local:8080/api/images/7/download',
  );
  assert.equal(client.imageDownloadUrl(7).includes('access_token'), false);

  await client.imageThumbnailBlob(7, { maxWidth: 280, quality: 70 });
  await client.imageDownloadBlob(7);
  assert.deepEqual(fetches.map((entry) => entry.url), [
    'http://nightshade.local:8080/api/images/7/thumbnail?maxWidth=280&quality=70',
    'http://nightshade.local:8080/api/images/7/download',
  ]);
  assert.equal(fetches[0].options.headers.Authorization, 'Bearer secret-token');
  assert.equal(fetches[1].options.headers.Authorization, 'Bearer secret-token');
});

test('remembered cookie sessions mint a WebSocket ticket', async () => {
  const openedUrls = [];
  class FakeWebSocket {
    static CONNECTING = 0;
    static OPEN = 1;

    constructor(url) {
      openedUrls.push(url);
      this.readyState = FakeWebSocket.CONNECTING;
    }
  }

  const client = createClient({ WebSocket: FakeWebSocket });
  client.configure('http://nightshade.local:8080', '', 'browser-1');
  client._useSessionCookie = true;
  client._csrfToken = 'cookie-csrf';
  let ticketRequests = 0;
  client.issueWebSocketTicket = async () => {
    ticketRequests += 1;
    return { ticket: 'cookie-ws-ticket', expiresInSeconds: 60 };
  };

  await client.connectWebSocket();

  assert.equal(ticketRequests, 1);
  assert.equal(openedUrls.length, 1);
  const socketUrl = new URL(openedUrls[0]);
  assert.equal(socketUrl.protocol, 'ws:');
  assert.equal(socketUrl.pathname, '/events');
  assert.equal(socketUrl.searchParams.get('ticket'), 'cookie-ws-ticket');
  assert.equal(socketUrl.searchParams.get('token'), null);
  assert.equal(socketUrl.searchParams.get('deviceId'), 'browser-1');
});

test('raw image data decodes the little-endian u16 wire contract', async () => {
  const bytes = Uint8Array.from([
    0x00, 0x00,
    0x01, 0x00,
    0xff, 0x00,
    0x00, 0x01,
    0x34, 0x12,
    0xff, 0xff,
  ]);
  const client = createClient({
    fetch: async () => ({
      ok: true,
      status: 200,
      arrayBuffer: async () => bytes.buffer,
      headers: { get: () => 'application/octet-stream' },
      text: async () => '',
    }),
  });
  client.configure('http://nightshade.local:8080', 'secret-token', 'browser-1');

  const pixels = await client.getLastRawImageData('cam-1');

  assert.deepEqual(Array.from(pixels), [0, 1, 255, 256, 0x1234, 0xffff]);
});

test('target search merges saved targets with installed catalog objects', async () => {
  const client = createClient();
  client._get = async (requestPath) => {
    if (requestPath.startsWith('/api/targets/search')) {
      return {
        targets: [{
          id: 7,
          name: 'Saved target',
          catalogId: 'USER-7',
          ra: 1,
          dec: 2,
        }],
      };
    }
    if (requestPath.startsWith('/api/planetarium/catalog/search')) {
      return {
        results: [{
          name: 'Andromeda Galaxy',
          catalogId: 'M31',
          ra: 10.684,
          raHours: 0.7123,
          dec: 41.269,
          type: 'Galaxy',
        }],
      };
    }
    throw new Error('Unexpected request: ' + requestPath);
  };

  const result = await client.targetsSearch('M31');

  assert.equal(result.targets.length, 2);
  assert.equal(result.targets[1].catalogId, 'M31');
  assert.equal(result.targets[1].ra, 0.7123);
  assert.equal(result.targets[1].id, null);
});

test('WebSocket heartbeat frames emit activity without becoming app events', async () => {
  class FakeWebSocket {
    static CONNECTING = 0;
    static OPEN = 1;

    constructor() {
      this.readyState = FakeWebSocket.CONNECTING;
      this.sent = [];
    }

    send(payload) {
      this.sent.push(payload);
    }

    close() {
      this.readyState = FakeWebSocket.CONNECTING;
    }
  }

  const client = createClient({ WebSocket: FakeWebSocket });
  client.configure('http://nightshade.local:8080', 'secret-token', 'browser-1');
  const activity = [];
  const events = [];
  client.on('ws:activity', (data) => activity.push(data));
  client.on('event', (data) => events.push(data));
  await client.connectWebSocket();
  client._ws.readyState = FakeWebSocket.OPEN;
  client._ws.onopen();
  client._ws.onmessage({ data: JSON.stringify({ type: 'pong' }) });

  assert.deepEqual(JSON.parse(JSON.stringify(activity)), [{ type: 'pong' }]);
  assert.deepEqual(events, []);
  client.disconnectWebSocket();
});
