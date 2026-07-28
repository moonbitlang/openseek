///|
declare type Message

///|
declare pub fn Message::parse(data : BytesView) -> Message raise CapnpError

///|
declare pub fn Message::encode(self : Message) -> Bytes
