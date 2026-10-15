///|
async test "simultaneously ready sources retain every event and source order" {
  let hub : @broadcast.Channel[String] = Channel(capacity=4)
  let notifications = hub.subscribe()
  let files : @async.Queue[String] = Queue(kind=Blocking(4))
  let controls : @async.Queue[String] = Queue(kind=Blocking(2))
  let browser : @async.Queue[String] = Queue(kind=Blocking(2))
  hub.publish("agent.started")
  hub.publish("agent.finished")
  files.put("fs.changed:1")
  files.put("fs.changed:2")
  controls.put("page.connected")
  controls.put("window.ready")
  browser.put("browser.event:1")
  browser.put("browser.event:2")
  let delivered : Array[String] = []
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      @event_mux.run(
        [
          () => controls.get(),
          () => notifications.next(),
          () => files.get(),
          () => browser.get(),
        ],
        event => {
          delivered.push(event)
          if delivered.length() == 8 {
            group.return_immediately(())
          }
        },
      )
    })
  })
  assert_eq(delivered.filter(event => event.has_prefix("agent.")), [
    "agent.started", "agent.finished",
  ])
  assert_eq(delivered.filter(event => event.has_prefix("fs.changed")), [
    "fs.changed:1", "fs.changed:2",
  ])
  assert_eq(delivered.filter(event => event.has_prefix("browser.event")), [
    "browser.event:1", "browser.event:2",
  ])
  assert_eq(
    delivered.filter(event => {
      event == "page.connected" || event == "window.ready"
    }),
    ["page.connected", "window.ready"],
  )
}

///|
async test "sources waking together preserve finish and browser events" {
  let hub : @async.Queue[String] = Queue(kind=Blocking(1))
  let browser : @async.Queue[String] = Queue(kind=Blocking(1))
  let ready : @async.Queue[Unit] = Queue(kind=Blocking(2))
  let delivered : Array[String] = []
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        @event_mux.run(
          [
            () => {
              ready.put(())
              hub.get()
            },
            () => {
              ready.put(())
              browser.get()
            },
          ],
          event => {
            delivered.push(event)
            if delivered.length() == 2 {
              group.return_immediately(())
            }
          },
        )
      })
      ready.get()
      ready.get()
      assert_true(hub.try_put("agent.finished"))
      assert_true(browser.try_put("browser.event"))
      @async.pause()
    })
  })
  assert_eq(delivered.length(), 2)
  assert_true(delivered.contains("agent.finished"))
  assert_true(delivered.contains("browser.event"))
}

///|
async test "cancelling delivery joins every blocked source reader" {
  let ready : @async.Queue[Unit] = Queue(kind=Blocking(2))
  let cleaned = [false, false]
  let delivered : Array[String] = []
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      let sources : Array[async () -> String] = []
      for index in 0..<2 {
        let input : @async.Queue[String] = Queue(kind=Blocking(1))
        sources.push(() => {
          defer {
            cleaned[index] = true
          }
          ready.put(())
          input.get()
        })
      }
      let task = group.spawn(() => {
        @event_mux.run(sources, event => delivered.push(event))
      })
      ready.get()
      ready.get()
      task.cancel()
      task.wait() catch {
        @async.WaitedTaskAlreadyCancelled => ()
        error => raise error
      }
    })
  })
  assert_eq(cleaned, [true, true])
  assert_eq(delivered, [])
}

///|
suberror TestFailure {
  SourceFailed
  DeliveryFailed
}

///|
async test "source and delivery failures retire the other readers" {
  for fail_source in [true, false] {
    let ready : @async.Queue[Unit] = Queue(kind=Blocking(2))
    let trigger : @async.Queue[String] = Queue(kind=Blocking(1))
    let blocked : @async.Queue[String] = Queue(kind=Blocking(1))
    let cleaned = [false, false]
    let mut failed = false
    @async.with_timeout(1000, () => {
      @async.with_task_group(group => {
        let task = group.spawn(allow_failure=true, () => {
          @event_mux.run(
            [
              () => {
                defer {
                  cleaned[0] = true
                }
                ready.put(())
                let event = trigger.get()
                if fail_source {
                  raise SourceFailed
                }
                event
              },
              () => {
                defer {
                  cleaned[1] = true
                }
                ready.put(())
                blocked.get()
              },
            ],
            _ => raise DeliveryFailed,
          )
        })
        ready.get()
        ready.get()
        trigger.put("agent.finished")
        task.wait() catch {
          SourceFailed if fail_source => failed = true
          DeliveryFailed if !fail_source => failed = true
          error => raise error
        }
      })
    })
    assert_true(failed)
    assert_eq(cleaned, [true, true])
  }
}
