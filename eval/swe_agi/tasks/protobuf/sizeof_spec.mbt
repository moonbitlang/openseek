///|
pub(open) trait Sized {
  fn size_of(Self) -> UInt
}

///|
pub fn[T : Sized] size_of(t : T) -> UInt {
  t.size_of()
}

///|
declare pub impl Sized for UInt

///|
declare pub impl Sized for UInt64

///|
declare pub impl Sized for Int

///|
declare pub impl Sized for Int64

///|
declare pub impl Sized for SInt

///|
declare pub impl Sized for SInt64

///|
declare pub impl Sized for Bool

///|
declare pub impl Sized for Enum

///|
declare pub impl Sized for Float

///|
declare pub impl Sized for Double

///|
declare pub impl Sized for Bytes

///|
declare pub impl Sized for String
