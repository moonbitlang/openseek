///|
priv struct Model {
  serial_percent : Int32
  workers : Int32
} derive(Eq)

///|
priv enum Msg {
  Serial(String)
  Workers(String)
  Reset
}

///|
fn initial_model() -> Model {
  { serial_percent: 20, workers: 8, }
}

///|
fn update(model : Model, message : Msg) -> Model {
  match message {
    Serial(text) => {
      let value : Int32 = @string.from_str(text) catch { _ => return model }
      { ..model, serial_percent: value.clamp(min=0, max=100), }
    }
    Workers(text) => {
      let value : Int32 = @string.from_str(text) catch { _ => return model }
      { ..model, workers: value.clamp(min=1, max=64), }
    }
    Reset => initial_model()
  }
}

///|
fn speedup(model : Model) -> Double {
  let serial = model.serial_percent.to_double() / 100.0
  1.0 / (serial + (1.0 - serial) / model.workers.to_double())
}

///|
fn hundredths(value : Double) -> String {
  let rounded = (value * 100.0 + 0.5).to_int()
  let fraction = rounded % 100
  let padding = if fraction < 10 { "0" } else { "" }
  "\{rounded / 100}.\{padding}\{fraction}"
}
