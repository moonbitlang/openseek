// Simulate only Proton's transport so the real frontend uses desktop/local
// capabilities. This does not launch a native CEF window.
export async function installDesktopTransport(page, app) {
  await page.exposeFunction('desktopTransportRequest', request => {
    app.requests.push(request);
    const error = app.rpcErrors.get(request.method);
    if (error !== undefined) throw new Error(error);
    if (request.method === 'app.system_appearance') return { dark: false };
    return app.replyFor(request);
  });
  await page.addInitScript(() => {
    const listeners = new Map();
    const events = { on(name, callback) {
      const callbacks = listeners.get(name) || new Set();
      listeners.set(name, callbacks);
      callbacks.add(callback);
      return () => callbacks.delete(callback);
    } };
    window.__MoonBit__ = {
      getTitlebarArea: async () => null,
      app: events, events,
      openseek: new Proxy({}, { get: (_, method) => async params => {
        if (method === 'host.connect') {
          for (const callback of listeners.get('openseek.agent.connected') || []) {
            callback({ payload: { stage: 'serving' } });
          }
        }
        return window.desktopTransportRequest({ method, params });
      } }),
    };
  });
}
