// JavaScript primitives not exposed by Rabbita's JS bindings.

///|
extern "js" fn is_native_error(value : @js.Value) -> Bool = "value => value instanceof Error"
