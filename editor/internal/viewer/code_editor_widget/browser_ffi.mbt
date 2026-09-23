// JavaScript primitives not exposed by Rabbita's JS bindings.

///|
extern "js" fn is_js_function(value : @js.Value) -> Bool = "value => typeof value === 'function'"
