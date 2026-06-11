///|
fn install_bridge(dispatch : @cmd.Dispatch[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    js_install_openseek_bridge(
      fn() { scheduler.add(dispatch(BridgeReady)) },
      fn(message) { scheduler.add(dispatch(BridgeUnavailable(message))) },
      fn(run_id, task, engine, selected_model, max_steps, cwd) {
        scheduler.add(
          dispatch(
            Started(run_id, task, engine, selected_model, max_steps, cwd),
          ),
        )
      },
      fn(
        run_id,
        event_name,
        content,
        tool_name,
        is_error,
        prompt_tokens,
        completion_tokens,
        answer,
        reason,
      ) {
        if decode_engine_event(
            event_name, content, tool_name, is_error, prompt_tokens, completion_tokens,
            answer, reason,
          )
          is Some(event) {
          scheduler.add(dispatch(Engine(run_id, event)))
        }
      },
      fn(run_id, message, exit_code, diagnostics) {
        scheduler.add(dispatch(Error(run_id, message, exit_code, diagnostics)))
      },
      fn(run_id, status, answer, exit_code) {
        scheduler.add(dispatch(Finished(run_id, status, answer, exit_code)))
      },
    )
  })
}

///|
fn start_openseek(
  dispatch : @cmd.Dispatch[Msg],
  task : String,
  selected_model : String,
  max_steps : String,
  cwd : String,
  api_key : String,
  session : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    js_start_openseek(task, selected_model, max_steps, cwd, api_key, session, fn(
      message,
    ) {
      scheduler.add(dispatch(Failed(message)))
    })
  })
}

///|
/// Refresh the sidebar's session list from the engine's durable store.
fn fetch_sessions(dispatch : @cmd.Dispatch[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    js_list_sessions(
      fn(text) {
        match decode_sessions_reply(text) {
          Some(items) => scheduler.add(dispatch(SessionsLoaded(items)))
          None =>
            scheduler.add(dispatch(SessionsFailed("malformed session list")))
        }
      },
      fn(message) { scheduler.add(dispatch(SessionsFailed(message))) },
    )
  })
}

///|
/// Load a durable session's transcript so the conversation can be resumed.
fn open_session(dispatch : @cmd.Dispatch[Msg], session_id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    js_load_session(
      session_id,
      fn(text) {
        match transcript_from_session_json(text) {
          Some(items) =>
            scheduler.add(dispatch(SessionLoaded(session_id, items)))
          None =>
            scheduler.add(
              dispatch(
                Failed("failed to load session \{session_id}: malformed data"),
              ),
            )
        }
      },
      fn(message) {
        scheduler.add(
          dispatch(Failed("failed to load session \{session_id}: " + message)),
        )
      },
    )
  })
}

///|
fn cancel_openseek(dispatch : @cmd.Dispatch[Msg], run_id : Int) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    js_cancel_openseek(run_id, fn(message) {
      scheduler.add(dispatch(Error(run_id, message, EmptyRunId, "")))
    })
  })
}

///|
extern "js" fn js_install_openseek_bridge(
  on_ready : () -> Unit,
  on_unavailable : (String) -> Unit,
  on_started : (Int, String, String, String, Int, String) -> Unit,
  on_event : (Int, String, String, String, Bool, Int, Int, String, String) -> Unit,
  on_error : (Int, String, Int, String) -> Unit,
  on_finished : (Int, String, String, Int) -> Unit,
) =
  #| (onReady, onUnavailable, onStarted, onEvent, onError, onFinished) => {
  #|   const text = (value) => value === undefined || value === null ? "" : String(value);
  #|   const number = (value, fallback = 0) => {
  #|     const parsed = Number(value);
  #|     return Number.isFinite(parsed) ? parsed : fallback;
  #|   };
  #|   const firstText = (...values) => {
  #|     for (const value of values) {
  #|       if (value !== undefined && value !== null) return String(value);
  #|     }
  #|     return "";
  #|   };
  #|   const install = (attempt = 0) => {
  #|     const root = globalThis.__MoonBit__;
  #|     const api = root && root.openseek;
  #|     const events = root && root.events;
  #|     if (!api || !api.start || !api.cancel || !events || !events.on) {
  #|       if (attempt > 120) {
  #|         onUnavailable("Bridge unavailable");
  #|       } else {
  #|         setTimeout(() => install(attempt + 1), 25);
  #|       }
  #|       return;
  #|     }
  #|     if (!globalThis.__openseekDesktopRabbitaBridgeInstalled) {
  #|       globalThis.__openseekDesktopRabbitaBridgeInstalled = true;
  #|       // Open the engine host: a single long-lived call whose task group
  #|       // owns the persistent --serve engine process. The promise only
  #|       // settles if the host stops; starts then fail with a clear error.
  #|       if (api.connect) {
  #|         try {
  #|           Promise.resolve(api.connect({})).catch(() => {});
  #|         } catch (ignored) {}
  #|       }
  #|       events.on("openseek.started", (event) => {
  #|         const payload = (event && event.payload) || {};
  #|         onStarted(
  #|           number(payload.run_id),
  #|           text(payload.task),
  #|           text(payload.engine),
  #|           text(payload.model),
  #|           number(payload.max_steps),
  #|           text(payload.cwd),
  #|         );
  #|       });
  #|       events.on("openseek.event", (event) => {
  #|         const payload = (event && event.payload) || {};
  #|         const raw = payload.event || {};
  #|         onEvent(
  #|           number(payload.run_id),
  #|           text(raw.event),
  #|           firstText(raw.content, raw.step),
  #|           text(raw.tool_name),
  #|           !!raw.is_error,
  #|           number(raw.prompt_tokens),
  #|           number(raw.completion_tokens),
  #|           text(raw.answer),
  #|           firstText(raw.reason, raw.error),
  #|         );
  #|       });
  #|       events.on("openseek.error", (event) => {
  #|         const payload = (event && event.payload) || {};
  #|         onError(
  #|           payload.run_id === undefined || payload.run_id === null ? -1 : number(payload.run_id, -1),
  #|           text(payload.message || "error"),
  #|           payload.exit_code === undefined || payload.exit_code === null ? -1 : number(payload.exit_code, -1),
  #|           text(payload.diagnostics),
  #|         );
  #|       });
  #|       events.on("openseek.finished", (event) => {
  #|         const payload = (event && event.payload) || {};
  #|         onFinished(
  #|           number(payload.run_id),
  #|           text(payload.status),
  #|           text(payload.answer),
  #|           payload.exit_code === undefined || payload.exit_code === null ? -1 : number(payload.exit_code, -1),
  #|         );
  #|       });
  #|     }
  #|     onReady();
  #|   };
  #|   install();
  #| }

///|
extern "js" fn js_start_openseek(
  task : String,
  selected_model : String,
  max_steps : String,
  cwd : String,
  api_key : String,
  session : String,
  on_error : (String) -> Unit,
) =
  #| (task, selectedModel, maxSteps, cwd, apiKey, session, onError) => {
  #|   const root = globalThis.__MoonBit__;
  #|   const api = root && root.openseek;
  #|   if (!api || !api.start) {
  #|     onError("OpenSeek bridge unavailable");
  #|     return;
  #|   }
  #|   const payload = { task };
  #|   const setText = (key, value) => {
  #|     const text = String(value || "").trim();
  #|     if (text) payload[key] = text;
  #|   };
  #|   setText("model", selectedModel);
  #|   setText("cwd", cwd);
  #|   setText("api_key", apiKey);
  #|   setText("session", session);
  #|   const parsedSteps = Number(maxSteps);
  #|   if (Number.isFinite(parsedSteps) && parsedSteps > 0) {
  #|     payload.max_steps = Math.floor(parsedSteps);
  #|   }
  #|   try {
  #|     const result = api.start(payload);
  #|     if (result && typeof result.catch === "function") {
  #|       result.catch((error) => onError(String((error && error.message) || error)));
  #|     }
  #|   } catch (error) {
  #|     onError(String((error && error.message) || error));
  #|   }
  #| }

///|
extern "js" fn js_list_sessions(
  on_loaded : (String) -> Unit,
  on_error : (String) -> Unit,
) =
  #| (onLoaded, onError) => {
  #|   const root = globalThis.__MoonBit__;
  #|   const api = root && root.openseek;
  #|   if (!api || !api.list_sessions) {
  #|     onError("OpenSeek bridge unavailable");
  #|     return;
  #|   }
  #|   try {
  #|     Promise.resolve(api.list_sessions({})).then(
  #|       (reply) => onLoaded(JSON.stringify(reply === undefined || reply === null ? {} : reply)),
  #|       (error) => onError(String((error && error.message) || error)),
  #|     );
  #|   } catch (error) {
  #|     onError(String((error && error.message) || error));
  #|   }
  #| }

///|
extern "js" fn js_load_session(
  session : String,
  on_loaded : (String) -> Unit,
  on_error : (String) -> Unit,
) =
  #| (session, onLoaded, onError) => {
  #|   const root = globalThis.__MoonBit__;
  #|   const api = root && root.openseek;
  #|   if (!api || !api.load_session) {
  #|     onError("OpenSeek bridge unavailable");
  #|     return;
  #|   }
  #|   try {
  #|     Promise.resolve(api.load_session({ session })).then(
  #|       (reply) => onLoaded(JSON.stringify(reply === undefined || reply === null ? {} : reply)),
  #|       (error) => onError(String((error && error.message) || error)),
  #|     );
  #|   } catch (error) {
  #|     onError(String((error && error.message) || error));
  #|   }
  #| }

///|
extern "js" fn js_cancel_openseek(run_id : Int, on_error : (String) -> Unit) =
  #| (runId, onError) => {
  #|   const root = globalThis.__MoonBit__;
  #|   const api = root && root.openseek;
  #|   if (!api || !api.cancel) {
  #|     onError("OpenSeek bridge unavailable");
  #|     return;
  #|   }
  #|   try {
  #|     const result = api.cancel({ run_id: runId });
  #|     if (result && typeof result.catch === "function") {
  #|       result.catch((error) => onError(String((error && error.message) || error)));
  #|     }
  #|   } catch (error) {
  #|     onError(String((error && error.message) || error));
  #|   }
  #| }
