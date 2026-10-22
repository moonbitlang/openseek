// The console's push-only service worker. It is served at /sw.js so its
// default scope `/` covers every application route; it has no fetch handler
// and caches nothing. The relay's payload contract and the reason the text
// lives here are in docs/plans/web-push.md. The strings mirror
// frontend/system_notification.mbt, which formats the window's banners.

const BodyMaxChars = 180;

const Text = {
  en: {
    finished: "Task finished",
    stepLimit: "Task stopped at the step limit",
    failed: "Task failed",
    ready: "The conversation is ready for you.",
    approvalTitle: "Permission required",
    approval: (tool, detail) => `${tool} is asking permission to ${detail}`,
    testTitle: "Notifications are on",
    test: "SeekMoon will notify this device when a task needs you.",
  },
  "zh-Hans": {
    finished: "任务已完成",
    stepLimit: "任务达到步数上限，已停止",
    failed: "任务失败",
    ready: "对话已就绪，请查看。",
    approvalTitle: "需要授权",
    approval: (tool, detail) => `${tool} 请求授权：${detail}`,
    testTitle: "通知已开启",
    test: "任务需要你处理时，SeekMoon 会通知这台设备。",
  },
  "zh-Hant": {
    finished: "任務已完成",
    stepLimit: "任務達到步數上限，已停止",
    failed: "任務失敗",
    ready: "對話已就緒，請檢視。",
    approvalTitle: "需要授權",
    approval: (tool, detail) => `${tool} 請求授權：${detail}`,
    testTitle: "通知已開啟",
    test: "任務需要你處理時，SeekMoon 會通知這台裝置。",
  },
  ja: {
    finished: "タスクが完了しました",
    stepLimit: "ステップ数の上限に達したためタスクを停止しました",
    failed: "タスクが失敗しました",
    ready: "チャットの準備ができました。ご確認ください。",
    approvalTitle: "許可が必要です",
    approval: (tool, detail) => `${tool} が許可を要求しています：${detail}`,
    testTitle: "通知がオンになりました",
    test: "タスクで対応が必要になると、SeekMoon がこのデバイスに通知します。",
  },
  es: {
    finished: "Tarea finalizada",
    stepLimit: "La tarea se detuvo al alcanzar el límite de pasos",
    failed: "La tarea falló",
    ready: "La conversación está lista para ti.",
    approvalTitle: "Se requiere permiso",
    approval: (tool, detail) => `${tool} solicita permiso para ${detail}`,
    testTitle: "Las notificaciones están activadas",
    test: "SeekMoon avisará a este dispositivo cuando una tarea te necesite.",
  },
};

// Keep whole code points while fitting a banner.
function truncate(text) {
  const chars = Array.from(text.trim());
  return chars.length > BodyMaxChars ? chars.slice(0, BodyMaxChars).join("") + "…" : chars.join("");
}

function finishTitle(text, kind, status) {
  if (kind === "cloud_finished") return status === "completed" ? text.finished : text.failed;
  if (status === "finished") return text.finished;
  if (status === "max_steps_exhausted") return text.stepLimit;
  return text.failed;
}

// What a payload shows. Anything unreadable still shows a notification:
// iOS revokes a subscription whose pushes show nothing.
function present(payload) {
  const fallback = { title: "SeekMoon", body: "", url: "/cloud" };
  if (!payload || typeof payload !== "object" || payload.v !== 1) return fallback;
  const text = Text[payload.locale] ?? Text.en;
  const url = typeof payload.url === "string" && payload.url.startsWith("/") ? payload.url : "/cloud";
  const answer = typeof payload.answer === "string" && payload.answer.trim() !== "" ? payload.answer : null;
  switch (payload.kind) {
    case "finished":
    case "cloud_finished":
      return {
        title: finishTitle(text, payload.kind, payload.status),
        body: answer ? truncate(answer) : text.ready,
        url,
        device: payload.device_name,
      };
    case "approval":
      return {
        title: text.approvalTitle,
        body: truncate(text.approval(String(payload.tool ?? ""), String(payload.detail ?? ""))),
        url,
        device: payload.device_name,
      };
    case "test":
      return { title: text.testTitle, body: text.test, url };
    default:
      return { ...fallback, url };
  }
}

function parse(event) {
  if (!event.data) return null;
  try {
    return event.data.json();
  } catch {
    return null;
  }
}

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));

self.addEventListener("push", (event) => {
  const shown = present(parse(event));
  event.waitUntil(
    self.registration.showNotification(shown.title, {
      body: shown.device ? `${shown.device} · ${shown.body}` : shown.body,
      // A newer push about the same conversation replaces the older one.
      tag: shown.url,
      icon: "/assets/icon-192.png",
      badge: "/assets/icon-192.png",
      data: { url: shown.url },
    }),
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = new URL(event.notification.data?.url ?? "/cloud", self.location.origin).href;
  event.waitUntil(
    (async () => {
      const windows = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
      for (const client of windows) {
        if (new URL(client.url).origin === self.location.origin && "focus" in client) {
          await client.focus();
          if ("navigate" in client) await client.navigate(url);
          return;
        }
      }
      await self.clients.openWindow(url);
    })(),
  );
});
