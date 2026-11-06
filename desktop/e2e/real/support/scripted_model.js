import { createServer } from 'node:http';

// An offline OpenAI-compatible `/chat/completions` endpoint. The engine
// streams every agent step from it; each test queues the replies its flow
// needs. Non-streaming side requests (titles, predictions) get an empty
// answer, so they never consume a scripted step.
export class ScriptedModel {
  constructor() {
    this.replies = [];
    this.server = createServer((request, response) => this.handle(request, response));
  }

  async listen() {
    await new Promise(resolve => this.server.listen(0, '127.0.0.1', resolve));
    return `http://127.0.0.1:${this.server.address().port}/chat/completions`;
  }

  close() {
    this.server.closeAllConnections();
    return new Promise(resolve => this.server.close(resolve));
  }

  // Queue a plain assistant message; content alone ends the turn.
  reply(text) {
    this.replies.push({ content: text });
  }

  reset() {
    this.replies = [];
  }

  async handle(request, response) {
    let body = '';
    for await (const chunk of request) body += chunk;
    if (request.url !== '/chat/completions') {
      response.writeHead(404).end();
      return;
    }
    const payload = JSON.parse(body);
    if (!payload.stream) {
      response.writeHead(200, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify({ choices: [{ message: { content: '{"text":null}' } }] }));
      return;
    }
    // An unscripted step is a test bug; answering keeps the turn finite and
    // makes the extra request visible in the transcript.
    const delta = this.replies.shift() ?? { content: 'Unscripted model request.' };
    response.writeHead(200, { 'Content-Type': 'text/event-stream' });
    response.end(`data: ${JSON.stringify({ choices: [{ delta }] })}\n\ndata: [DONE]\n\n`);
  }
}
