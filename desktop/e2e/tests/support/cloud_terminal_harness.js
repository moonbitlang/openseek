import { cloudOrigin } from './cloud_harness.js';

export class CloudTerminalHarness {
  constructor(page) {
    this.page = page;
    this.connections = [];
    this.authenticate = true;
    this.holdInput = false;
  }

  async install() {
    await this.page.routeWebSocket(`${cloudOrigin.replace('https:', 'wss:')}/v1/sessions/*/terminal`, socket => {
      const connection = {
        socket, url: socket.url(), session: socket.url().split('/').at(-2),
        frames: [], requests: [], terminals: [], closed: false,
      };
      this.connections.push(connection);
      socket.onClose(() => { connection.closed = true; });
      socket.onMessage(message => {
        const frame = JSON.parse(String(message));
        connection.frames.push(frame);
        if (frame.type === 'auth') {
          if (this.authenticate) socket.send(JSON.stringify({ type: 'authenticated' }));
          return;
        }
        connection.requests.push(frame);
        let result = {};
        if (frame.method === 'terminal.open') {
          const id = `terminal-${connection.terminals.length + 1}`;
          connection.terminals.push({ id, ...frame.params });
          result = { id };
        }
        if (frame.method === 'terminal.input' && this.holdInput) return;
        socket.send(JSON.stringify({ jsonrpc: '2.0', id: frame.id, result }));
      });
    });
  }

  requests(method) {
    return this.connections.flatMap(connection => connection.requests).filter(request => request.method === method);
  }

  output(connection, text, sequence = 1, id = 'terminal-1') {
    connection.socket.send(JSON.stringify({ jsonrpc: '2.0', method: 'terminal.output', params: {
      id, sequence, data: Buffer.from(text).toString('base64'),
    } }));
  }

  exit(connection, code = 0, id = 'terminal-1') {
    connection.socket.send(JSON.stringify({ jsonrpc: '2.0', method: 'terminal.exit', params: { id, code } }));
  }
}
