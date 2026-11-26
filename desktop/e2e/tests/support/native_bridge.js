// Shared Playwright mock for the Proton native host bridge (`window.__MoonBit__`).
// Replaces only the host transport so production frontend code, codecs, DOM
// events, and focus handling still run in Chromium.
export async function installNativeBridge(
  page,
  { hostProtocol, onRequest, onNotification } = {},
) {
  await page.exposeFunction('__desktopBridgeRequest', request => onRequest(request));
  const hasNotification = typeof onNotification === 'function';
  if (hasNotification) {
    await page.exposeFunction('__desktopBridgeNotification', (method, params) =>
      onNotification(method, params),
    );
  }
  await page.addInitScript(({ protocol, hasNotification }) => {
    const listeners = new Map();
    const events = {
      on(name, callback) {
        const callbacks = listeners.get(name) || new Set();
        listeners.set(name, callbacks);
        callbacks.add(callback);
        return () => callbacks.delete(callback);
      },
    };
    window.desktopEvent = (name, payload) => {
      for (const callback of listeners.get(name) || []) callback({ payload });
    };
    window.titlebarArea = null;
    window.__MoonBit__ = {
      getTitlebarArea: async () => {
        if (window.titlebarFullscreen) return null;
        if (window.customTitlebarHeight) {
          return { x: 0, y: 0, width: innerWidth - 138, height: window.customTitlebarHeight };
        }
        return window.titlebarArea;
      },
      app: events,
      events,
      ...(hasNotification
        ? {
            notification: {
              show: params => window.__desktopBridgeNotification('show', params),
              setBadge: params => window.__desktopBridgeNotification('setBadge', params),
            },
          }
        : {}),
      openseek: new Proxy({}, {
        get: (_, method) => async params => {
          if (method === 'host.connect') {
            window.desktopEvent('openseek.agent.connected', { protocol });
          }
          const reply = await window.__desktopBridgeRequest({ method, params });
          if (method === 'app.set_titlebar_style' && reply?.custom_overlay) {
            // The real host rounds to a native row before reporting CSS geometry.
            window.customTitlebarHeight = Math.round(params.height);
          }
          return reply;
        },
      }),
    };
  }, { protocol: hostProtocol, hasNotification });

  return {
    emit: (name, payload) =>
      page.evaluate(([eventName, eventPayload]) => window.desktopEvent(eventName, eventPayload), [name, payload]),
  };
}
