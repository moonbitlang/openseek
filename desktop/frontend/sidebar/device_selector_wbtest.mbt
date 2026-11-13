///|
fn selector_account(
  page~ : Page,
  online_devices~ : Array[DeviceChoice],
) -> Account {
  {
    login: "octocat",
    avatar: "",
    busy: false,
    notice: None,
    page,
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
test "the device selector offers Cloud and online devices with the page's own one checked" {
  let mac = DeviceChoice::{ id: "d_mac", name: "Mac", }
  let pc = DeviceChoice::{ id: "d_pc", name: "PC", }
  let menu = selector_account(page=DevicePage(id="d_mac", name=Some("Mac")), online_devices=[
    mac, pc,
  ]).device_menu(_ => @cmd.none, add_device=None, locale=English)
  assert_eq(menu.label, "Choose a device")
  assert_eq(menu_rows(menu), [
    ("Cloud", true, false),
    ("separator", false, false),
    ("Mac", false, true),
    ("PC", true, false),
  ])
}

///|
test "a Cloud page's selector checks Cloud, and an empty roster says no device is online" {
  let mac = DeviceChoice::{ id: "d_mac", name: "Mac", }
  let cloud = selector_account(page=CloudPage, online_devices=[mac]).device_menu(
    _ => @cmd.none,
    add_device=None,
    locale=English,
  )
  assert_eq(menu_rows(cloud), [
    ("Cloud", false, true),
    ("separator", false, false),
    ("Mac", true, false),
  ])
  let empty = selector_account(page=DevicePage(id="offline", name=None), online_devices=[]).device_menu(
    _ => @cmd.none,
    add_device=None,
    locale=English,
  )
  assert_eq(menu_rows(empty), [
    ("Cloud", true, false),
    ("separator", false, false),
    ("No devices online", false, false),
  ])
}

///|
test "a relay that publishes the apps ends the menu with a way to add a device" {
  let mac = DeviceChoice::{ id: "d_mac", name: "Mac", }
  let rows = online_devices => {
    menu_rows(
      selector_account(page=CloudPage, online_devices~).device_menu(
        _ => @cmd.none,
        add_device=Some(@cmd.none),
        locale=English,
      ),
    )
  }
  assert_eq(rows([mac]), [
    ("Cloud", false, true),
    ("separator", false, false),
    ("Mac", true, false),
    ("separator", false, false),
    ("Add a device", true, false),
  ])
  assert_eq(rows([]), [
    ("Cloud", false, true),
    ("separator", false, false),
    ("No devices online", false, false),
    ("separator", false, false),
    ("Add a device", true, false),
  ])
}
