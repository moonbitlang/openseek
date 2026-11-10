///|
async fn resource_layout(root : String) -> String {
  let tree = StringBuilder()
  tree.write_string(".")
  async fn visit(directory : String, prefix : String) -> Unit {
    let directories : Array[String] = []
    for name in @fs.readdir(directory) {
      // Bundled workflows may leave `_build` beside their scripts. The two
      // human-oriented tutorials stay on disk, but the model looks facts up
      // in `language/` and `toolchain/` instead.
      if !name.has_prefix(".") &&
        name != "_build" &&
        !name.has_prefix("gmachine") &&
        name != "for-go-programmers" &&
        @fs.kind("\{directory}/\{name}", follow_symlink=false) is Directory {
        directories.push(name)
      }
    }
    // String's default ordering is length-first; directory trees use lexical order.
    directories.sort_by((a, b) => {
      let length = if a.length() < b.length() { a.length() } else { b.length() }
      for i in 0..<length {
        if a[i] != b[i] {
          return a[i].compare(b[i])
        }
      }
      a.length().compare(b.length())
    })
    for index, name in directories {
      let last = index == directories.length() - 1
      let branch = if last { "└── " } else { "├── " }
      tree.write_string("\n\{prefix}\{branch}\{name}")
      let next_prefix = prefix + (if last { "    " } else { "│   " })
      visit("\{directory}/\{name}", next_prefix)
    }
  }
  visit(root, "")
  tree.to_string()
}
