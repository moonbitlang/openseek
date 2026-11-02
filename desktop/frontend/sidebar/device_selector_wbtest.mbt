///|
fn selector_account(
  device~ : DeviceChoice?,
  online_devices~ : Array[DeviceChoice],
) -> Account {
  {
    login: "octocat",
    avatar: "",
    busy: false,
    notice: None,
    device,
    online_devices,
  }
}

///|
fn menu_rows(
  definition : @action_menu.Definition,
) -> Array[(String, Bool, Bool)] {
  definition.entries.map(entry => {
    guard entry is Action(item) else { return ("separator", false, false) }
    (item.label, item.enabled, item.icon is Some(_))
  })
}

///|
test "the device selector offers online devices with the page's own one checked" {
  let mac = DeviceChoice::{ id: "d_mac", name: "Mac", }
  let pc = DeviceChoice::{ id: "d_pc", name: "PC", }
  let menu = selector_account(device=Some(mac), online_devices=[mac, pc]).device_menu(
    _ => @cmd.none,
    locale=English,
  )
  assert_eq(menu.label, "Choose a device")
  assert_eq(menu_rows(menu), [("Mac", false, true), ("PC", true, false)])
}

///|
test "a Cloud page's selector checks nothing, and an empty roster says no device is online" {
  let mac = DeviceChoice::{ id: "d_mac", name: "Mac", }
  let cloud = selector_account(device=None, online_devices=[mac]).device_menu(
    _ => @cmd.none,
    locale=English,
  )
  assert_eq(menu_rows(cloud), [("Mac", true, false)])
  let empty = selector_account(device=None, online_devices=[]).device_menu(
    _ => @cmd.none,
    locale=English,
  )
  assert_eq(menu_rows(empty), [("No devices online", false, false)])
}
