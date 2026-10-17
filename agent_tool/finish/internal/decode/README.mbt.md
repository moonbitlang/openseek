# agent_tool/finish/internal/decode

Argument decoding for the `finish` control tool: the one call an agent makes to
end its run and hand back a final answer.

This package is internal to `agent_tool/finish`. It owns only argument-shape
decoding; what happens to the answer afterwards stays in the parent package.

## `decode` cannot fail — on purpose

Every other tool's decoder raises on a malformed payload, so the error goes back
to the model and it retries with corrected arguments. `finish` is the one place
where that is the wrong behavior: the call whose entire job is to *stop* the run
would instead keep an already-finished run alive, and the retry has nothing new
to say.

So the signature is `Json -> FinishInput`, with no `raise`. Anything that is not
a string `answer` decodes to the empty answer, and the run ends.

```mbt check
///|
test "a well-formed call carries the answer through" {
  debug_inspect(
    @decode.decode({ "answer": "All 482 tasks pass; moon check is clean." }),
    content=(
      #|{ answer: "All 482 tasks pass; moon check is clean." }
    ),
  )
}

///|
test "every malformed shape ends the run with an empty answer" {
  // Missing field.
  debug_inspect(
    @decode.decode(Json::empty_object()),
    content=(
      #|{ answer: "" }
    ),
  )
  // Present but not a string — a number, an object, or null.
  debug_inspect(
    @decode.decode({ "answer": 42 }),
    content=(
      #|{ answer: "" }
    ),
  )
  debug_inspect(
    @decode.decode({ "answer": null }),
    content=(
      #|{ answer: "" }
    ),
  )
  // Not even an object.
  debug_inspect(
    @decode.decode(null),
    content=(
      #|{ answer: "" }
    ),
  )
  debug_inspect(
    @decode.decode(["answer"]),
    content=(
      #|{ answer: "" }
    ),
  )
}
```

The trade this makes is explicit: a garbled `finish` loses the answer text rather
than trapping the agent in a retry loop it cannot escape. Extra fields are
ignored, and an empty answer is a legitimate decode result, not a signal of
failure — the parent package cannot distinguish "the model sent `answer: ""`"
from "the model sent nonsense", and does not need to.

```mbt check
///|
test "extra fields are ignored" {
  debug_inspect(
    @decode.decode({ "answer": "done", "confidence": 0.9 }),
    content=(
      #|{ answer: "done" }
    ),
  )
}
```
