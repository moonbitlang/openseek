///|
/// Native menu labels follow the window's effective UI language. Role items
/// retain Proton's native key equivalents and responder-chain behavior.
pub fn localized_menu(language : String) -> @proton.MenuBar {
  let zh = language == "zh-Hans"
  MenuBar(menus=[
    @proton.Menu::role(Application, label="SeekMoon", items=[
      @proton.MenuItem::role(
        Hide,
        label=if zh { "隐藏 SeekMoon" } else { "Hide SeekMoon" },
      ),
      @proton.MenuItem::role(
        HideOthers,
        label=if zh { "隐藏其他应用" } else { "Hide Others" },
      ),
      @proton.MenuItem::role(
        ShowAll,
        label=if zh { "显示全部" } else { "Show All" },
      ),
      @proton.MenuItem::separator(),
      @proton.MenuItem::role(
        Quit,
        label=if zh { "退出 SeekMoon" } else { "Quit SeekMoon" },
      ),
    ]),
    @proton.Menu::role(Edit, label=if zh { "编辑" } else { "Edit" }, items=[
      @proton.MenuItem::role(Undo, label=if zh { "撤销" } else { "Undo" }),
      @proton.MenuItem::role(Redo, label=if zh { "重做" } else { "Redo" }),
      @proton.MenuItem::separator(),
      @proton.MenuItem::role(Cut, label=if zh { "剪切" } else { "Cut" }),
      @proton.MenuItem::role(Copy, label=if zh { "复制" } else { "Copy" }),
      @proton.MenuItem::role(Paste, label=if zh { "粘贴" } else { "Paste" }),
      @proton.MenuItem::role(
        SelectAll,
        label=if zh { "全选" } else { "Select All" },
      ),
    ]),
    Menu(if zh { "开发者" } else { "Developer" }, items=[
      @proton.MenuItem::command(
        @commands.app_open_devtools.name(),
        if zh {
          "打开开发者工具"
        } else {
          "Open Developer Tools"
        },
      ),
    ]),
    @proton.Menu::role(Window, label=if zh { "窗口" } else { "Window" }, items=[
      @proton.MenuItem::role(
        Minimize,
        label=if zh { "最小化" } else { "Minimize" },
      ),
      @proton.MenuItem::role(Zoom, label=if zh { "缩放" } else { "Zoom" }),
      @proton.MenuItem::command(
        @commands.CloseFocusedMenuCommand,
        if zh {
          "关闭"
        } else {
          "Close"
        },
        key="w",
      ),
    ]),
  ])
}
