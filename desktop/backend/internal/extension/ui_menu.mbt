///|
/// Native menu labels follow the window's effective UI language. Role items
/// retain Proton's native key equivalents and responder-chain behavior.
pub fn localized_menu(language : String) -> @proton.MenuBar {
  MenuBar(menus=[
    @proton.Menu::role(Application, label="SeekMoon", items=[
      @proton.MenuItem::role(
        Hide,
        label=match language {
          "zh-Hans" => "隐藏 SeekMoon"
          "zh-Hant" => "隱藏 SeekMoon"
          "ja" => "SeekMoon を隠す"
          _ => "Hide SeekMoon"
        },
      ),
      @proton.MenuItem::role(
        HideOthers,
        label=match language {
          "zh-Hans" => "隐藏其他应用"
          "zh-Hant" => "隱藏其他應用程式"
          "ja" => "ほかを隠す"
          _ => "Hide Others"
        },
      ),
      @proton.MenuItem::role(
        ShowAll,
        label=match language {
          "zh-Hans" => "显示全部"
          "zh-Hant" => "顯示全部"
          "ja" => "すべてを表示"
          _ => "Show All"
        },
      ),
      @proton.MenuItem::separator(),
      @proton.MenuItem::role(
        Quit,
        label=match language {
          "zh-Hans" => "退出 SeekMoon"
          "zh-Hant" => "結束 SeekMoon"
          "ja" => "SeekMoon を終了"
          _ => "Quit SeekMoon"
        },
      ),
    ]),
    @proton.Menu::role(
      Edit,
      label=match language {
        "zh-Hans" => "编辑"
        "zh-Hant" => "編輯"
        "ja" => "編集"
        _ => "Edit"
      },
      items=[
        @proton.MenuItem::role(
          Undo,
          label=match language {
            "zh-Hans" => "撤销"
            "zh-Hant" => "復原"
            "ja" => "取り消す"
            _ => "Undo"
          },
        ),
        @proton.MenuItem::role(
          Redo,
          label=match language {
            "zh-Hans" => "重做"
            "zh-Hant" => "重做"
            "ja" => "やり直す"
            _ => "Redo"
          },
        ),
        @proton.MenuItem::separator(),
        @proton.MenuItem::role(
          Cut,
          label=match language {
            "zh-Hans" => "剪切"
            "zh-Hant" => "剪下"
            "ja" => "カット"
            _ => "Cut"
          },
        ),
        @proton.MenuItem::role(
          Copy,
          label=match language {
            "zh-Hans" => "复制"
            "zh-Hant" => "複製"
            "ja" => "コピー"
            _ => "Copy"
          },
        ),
        @proton.MenuItem::role(
          Paste,
          label=match language {
            "zh-Hans" => "粘贴"
            "zh-Hant" => "貼上"
            "ja" => "ペースト"
            _ => "Paste"
          },
        ),
        @proton.MenuItem::role(
          SelectAll,
          label=match language {
            "zh-Hans" => "全选"
            "zh-Hant" => "全選"
            "ja" => "すべてを選択"
            _ => "Select All"
          },
        ),
      ],
    ),
    Menu(
      match language {
        "zh-Hans" => "开发者"
        "zh-Hant" => "開發者"
        "ja" => "開発者"
        _ => "Developer"
      },
      items=[
        @proton.MenuItem::command(
          @commands.app_open_devtools.name(),
          match language {
            "zh-Hans" => "打开开发者工具"
            "zh-Hant" => "開啟開發者工具"
            "ja" => "開発者ツールを開く"
            _ => "Open Developer Tools"
          },
        ),
      ],
    ),
    @proton.Menu::role(
      Window,
      label=match language {
        "zh-Hans" => "窗口"
        "zh-Hant" => "視窗"
        "ja" => "ウィンドウ"
        _ => "Window"
      },
      items=[
        @proton.MenuItem::role(
          Minimize,
          label=match language {
            "zh-Hans" => "最小化"
            "zh-Hant" => "最小化"
            "ja" => "最小化"
            _ => "Minimize"
          },
        ),
        @proton.MenuItem::role(
          Zoom,
          label=match language {
            "zh-Hans" => "缩放"
            "zh-Hant" => "縮放"
            "ja" => "ズーム"
            _ => "Zoom"
          },
        ),
        @proton.MenuItem::command(
          @commands.CloseFocusedMenuCommand,
          match language {
            "zh-Hans" => "关闭"
            "zh-Hant" => "關閉"
            "ja" => "閉じる"
            _ => "Close"
          },
          key="w",
        ),
      ],
    ),
  ])
}
