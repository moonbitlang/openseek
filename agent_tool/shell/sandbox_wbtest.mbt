///|
test "sandbox trusts only narrow moon source-writing commands" {
  assert_true(mode_for("moon fmt") is TrustedSourceWrite)
  assert_true(mode_for("moon new my_project") is TrustedSourceWrite)
  assert_true(mode_for("moon new ./pkg") is TrustedSourceWrite)
  assert_true(mode_for("cd sub && moon new app") is TrustedSourceWrite)
  assert_true(mode_for("moon new --help") is SourceReadOnly)
  assert_true(mode_for("moon new --name demo -- --help") is TrustedSourceWrite)
  assert_true(mode_for("moon info") is TrustedSourceWrite)
  assert_true(
    mode_for("moon ide rename old new --loc main.mbt:1:8 --apply")
    is TrustedSourceWrite,
  )
  assert_true(mode_for("moon fmt && moon check") is TrustedSourceWrite)
  assert_true(mode_for("cd ./pkg && moon fmt") is TrustedSourceWrite)
  assert_true(mode_for("moon fmt >/dev/null") is TrustedSourceWrite)
  assert_true(mode_for("moon info > /tmp/log") is TrustedSourceWrite)
  assert_true(mode_for("moon test --update 2>/tmp/err") is TrustedSourceWrite)
  assert_true(mode_for("moon fmt > out.log") is TrustedSourceWrite)
  assert_true(mode_for("moon check") is TrustedSourceWrite)
  assert_true(mode_for("moon build") is TrustedSourceWrite)
  assert_true(mode_for("moon test") is TrustedSourceWrite)
  assert_true(mode_for("moon run cmd/main") is TrustedSourceWrite)
  assert_true(mode_for("moon run cmd/main -- --help") is TrustedSourceWrite)
  assert_true(mode_for("moon run cmd/main -- -u") is TrustedSourceWrite)
  assert_true(mode_for("moon run cmd/main --help") is SourceReadOnly)
  assert_true(
    mode_for("moon run -e 'fn main { println(1) }'") is SourceReadOnly,
  )
  assert_true(mode_for("moon run -e'fn main { println(1) }'") is SourceReadOnly)
  assert_true(
    mode_for("moon run --target native -e 'fn main { println(1) }'")
    is SourceReadOnly,
  )
  assert_true(mode_for("moon run -") is SourceReadOnly)
  assert_true(mode_for("moon run -- -") is SourceReadOnly)
  assert_true(mode_for("moon run --target native -") is SourceReadOnly)
  assert_true(mode_for("moon run --target native -- -") is SourceReadOnly)
  assert_true(mode_for("moon fmt --check") is SourceReadOnly)
  assert_true(mode_for("moon check --help") is SourceReadOnly)
  assert_true(mode_for("cd pkg && moon fmt") is TrustedSourceWrite)
  assert_true(mode_for("moon fmt && git diff") is TrustedSourceWrite)
  assert_true(mode_for("moon fmt > main.mbt") is SourceReadOnly)
  assert_true(mode_for("moon fmt 2> main.mbt") is SourceReadOnly)
  assert_true(mode_for("moon fmt 1>> main.mbt") is SourceReadOnly)
  assert_true(mode_for("cd ./pkg && moon fmt > main.mbt") is SourceReadOnly)
  assert_true(mode_for("moon fmt 2>&1") is TrustedSourceWrite)
  assert_true(mode_for("sed -i '' 's/a/b/' *.mbt") is SourceReadOnly)
}

///|
#cfg(not(platform="windows"))
async test "sandbox preblocks source-writing script snippets" {
  let root = "/workspace"
  assert_true(
    tree_target(
      "python3 -c 'import os; os.makedirs(\"_build/gen\", exist_ok=True); open(\"_build/gen/main.mbt\", \"w\").write(\"pub fn generated() -> Int { 1 }\\\\n\"); os.rename(\"_build/gen\", \"pkg\")'",
      root,
      Some(root),
    )
    is Some("/workspace/pkg"),
  )
  assert_true(
    tree_target(
      "python3 -c 'import os; src=\"_build/gen\"; dst=\"pkg\"; os.makedirs(src, exist_ok=True); open(src + \"/main.mbt\", \"w\").write(\"pub fn generated() -> Int { 1 }\\\\n\"); os.rename(src, dst)'",
      root,
      Some(root),
    )
    is Some("/workspace/pkg"),
  )
  assert_true(
    tree_target(
      "mkdir -p _build/gen && printf source > _build/gen/main.mbt && python3 -c 'import os; os.rename(\"_build/gen\", \"pkg\")'",
      root,
      Some(root),
    )
    is Some("/workspace/pkg"),
  )
  assert_true(
    tree_target(
      "python3 -c 'import os; open(\"_build/generated.txt\", \"w\").write(\"asset\"); os.rename(\"_build/generated.txt\", \"asset.txt\")'",
      root,
      Some(root),
    )
    is None,
  )
  assert_true(
    tree_target(
      "python3 -c 'import shutil; shutil.copyfile(\"replacement.txt\", \"main.mbt\")'",
      root,
      Some(root),
    )
    is Some("/workspace/main.mbt"),
  )
  assert_true(
    tree_target(
      "node -e 'const fs = require(\"fs\"); fs.cpSync(\"_build/gen\", \"pkg\", { recursive: true })'",
      root,
      Some(root),
    )
    is Some("/workspace/pkg"),
  )
  assert_true(
    tree_target(
      "python3 -c 'print(open(\"main.mbt\").read())'",
      root,
      Some(root),
    )
    is None,
  )
  assert_true(
    tree_target(
      "python3 -c 'import sys; sys.stdout.write(open(\"main.mbt\").read())'",
      root,
      Some(root),
    )
    is None,
  )
  assert_true(
    tree_target(
      "python3 -c 'import sys; sys.stderr.write(open(\"main.mbt\").read())'",
      root,
      Some(root),
    )
    is None,
  )
  assert_true(
    tree_target(
      "python3 -c 'print(\"w\"); print(open(\"main.mbt\").read())'",
      root,
      Some(root),
    )
    is None,
  )
  assert_true(
    tree_target(
      "python3 -c 'import sys; sys.stdout.buffer.write(open(\"main.mbt\", \"rb\").read())'",
      root,
      Some(root),
    )
    is None,
  )
  assert_true(
    tree_target(
      "python3 -c 'open(\"/tmp/probe.mbt\", \"w\").write(\"x\")'",
      root,
      Some(root),
    )
    is None,
  )
  assert_true(
    tree_target(
      "python3 -c 'print(\"main.mbt\".replace(\".mbt\", \".txt\"))'",
      root,
      Some(root),
    )
    is None,
  )
  assert_true(
    tree_target(
      "python3 -c 'from pathlib import Path; Path(\"main.mbt\").write_text(\"pub fn answer() -> Int { 1 }\\\\n\")' 2>/dev/null || true",
      root,
      Some(root),
    )
    is Some("/workspace/main.mbt"),
  )
  assert_true(
    tree_target(
      "awk 'BEGIN { print \"pub fn answer() -> Int { 43 }\" > \"main.mbt\" }' 2>/dev/null || true",
      root,
      Some(root),
    )
    is Some("/workspace/main.mbt"),
  )
  assert_true(
    tree_target(
      "awk -v marker=.mbt 'BEGIN { if (1 > 0) print marker }'",
      root,
      Some(root),
    )
    is None,
  )
  assert_true(
    tree_target(
      "sh -c 'mkdir -p _build/gen; printf source > _build/gen/main.mbt; mv _build/gen pkg'",
      root,
      Some(root),
    )
    is Some("/workspace/pkg"),
  )
  assert_true(
    tree_target(
      "bash --noprofile -c 'mkdir -p _build/gen; printf source > _build/gen/main.mbt; mv _build/gen pkg'",
      root,
      Some(root),
    )
    is Some("/workspace/pkg"),
  )
  assert_true(
    tree_target(
      "bash -o pipefail -c 'mkdir -p _build/gen; printf source > _build/gen/main.mbt; mv _build/gen pkg'",
      root,
      Some(root),
    )
    is Some("/workspace/pkg"),
  )
  assert_true(
    tree_target(
      "dash -c 'mkdir -p _build/gen; printf source > _build/gen/main.mbt; mv _build/gen pkg'",
      root,
      Some(root),
    )
    is Some("/workspace/pkg"),
  )
  assert_true(
    tree_target(
      "ksh -c 'mkdir -p _build/gen; printf source > _build/gen/main.mbt; mv _build/gen pkg'",
      root,
      Some(root),
    )
    is Some("/workspace/pkg"),
  )
  assert_true(
    tree_target(
      "node -e 'const fs = require(\"fs\"); fs.mkdirSync(\"_build/gen\", { recursive: true }); fs.writeFileSync(\"_build/gen/main.mbt\", \"pub fn generated() -> Int { 1 }\\\\n\"); fs.renameSync(\"_build/gen\", \"pkg\")'",
      root,
      Some(root),
    )
    is Some("/workspace/pkg"),
  )
}

///|
#cfg(not(platform="windows"))
async test "sandbox preblocks command-line created source directories" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-created-dir-", root => {
    @fs.write_file(
      "\{root}/main.mbt",
      "pub fn answer() -> Int { 42 }\n",
      create_mode=CreateOrTruncate,
    )
    let target = tree_target(
      "mkdir backup && cp main.mbt backup 2>/dev/null || true",
      root,
      Some(root),
    )
    assert_true(target == Some("\{root}/backup"))
  })
}

///|
#cfg(not(platform="windows"))
async test "sandbox preblocks scripted existing source tree moves" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-script-source-dir-", root => {
    @fs.mkdir("\{root}/pkg")
    @fs.write_file(
      "\{root}/pkg/main.mbt",
      "pub fn answer() -> Int { 42 }\n",
      create_mode=CreateOrTruncate,
    )
    let target = tree_target(
      "python3 -c 'import os; os.rename(\"pkg\", \"pkg.bak\")' 2>/dev/null || true",
      root,
      Some(root),
    )
    assert_true(target == Some("\{root}/pkg.bak"))
  })
}

///|
#cfg(not(platform="windows"))
async test "sandbox keeps guarded cd cwd visible after semicolon" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-guarded-cd-", root => {
    @fs.mkdir("\{root}/pkg")
    @fs.mkdir("\{root}/pkg/sub")
    @fs.write_file(
      "\{root}/pkg/sub/main.mbt",
      "pub fn answer() -> Int { 42 }\n",
      create_mode=CreateOrTruncate,
    )
    let target = tree_target("cd ./pkg && true; rm -rf sub", root, Some(root))
    assert_true(target == Some("\{root}/pkg/sub"))
  })
}

///|
#cfg(not(platform="windows"))
async test "sandbox preblocks scripted external source tree imports" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-script-external-dir-", root => {
    let workspace = "\{root}/workspace"
    let generated = "\{root}/generated_pkg"
    let generated_file = "\{root}/generated.mbt"
    @fs.mkdir(workspace)
    @fs.mkdir(generated)
    @fs.write_file(
      "\{generated}/main.mbt",
      "pub fn generated() -> Int { 1 }\n",
      create_mode=CreateOrTruncate,
    )
    @vfs.FileSystem({
      "generated.mbt": "pub fn generated_file() -> Int { 1 }\n",
    }).write_to(root)
    let target = tree_target(
      "python3 -c 'import shutil; shutil.move(\"\{generated}\", \"pkg\")'",
      workspace,
      Some(workspace),
    )
    assert_true(target == Some("\{workspace}/pkg"))
    let copy_target = tree_target(
      "python3 -c 'import shutil; shutil.copy(\"\{generated_file}\", \"pkg\")'",
      workspace,
      Some(workspace),
    )
    assert_true(copy_target == Some("\{workspace}/pkg"))
  })
}

///|
#cfg(not(platform="windows"))
async test "sandbox preblocks common source-writing commands" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-common-writers-", root => {
    @fs.write_file(
      "\{root}/main.mbt",
      "pub fn answer() -> Int { 42 }\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{root}/replacement.txt",
      "pub fn answer() -> Int { 43 }\n",
      create_mode=CreateOrTruncate,
    )
    @fs.mkdir("\{root}/pkg")
    @fs.write_file(
      "\{root}/pkg/main.mbt",
      "pub fn package_answer() -> Int { 42 }\n",
      create_mode=CreateOrTruncate,
    )
    @fs.mkdir("\{root}/src")
    @fs.mkdir("\{root}/src/pkg")
    @fs.mkdir("\{root}/_build")
    @fs.write_file(
      "\{root}/src/pkg/main.mbt",
      "pub fn nested_package_answer() -> Int { 42 }\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{root}/_build/main.mbt",
      "pub fn generated() -> Int { 42 }\n",
      create_mode=CreateOrTruncate,
    )
    @fs.symlink(target="main.mbt", "\{root}/out.log")
    let real_root = @fs.realpath(root)
    let main_path = "\{real_root}/main.mbt"
    let src_pkg_path = "\{real_root}/src/pkg"
    let backup_path = "\{real_root}/backup.mbt"
    assert_true(
      is_some_path(
        tree_target(
          "cp replacement.txt main.mbt 2>/dev/null || true",
          real_root,
          Some(real_root),
        ),
        main_path,
      ),
    )
    assert_true(
      is_some_path(
        tree_target(
          "cp replacement.txt out.log 2>/dev/null || true",
          real_root,
          Some(real_root),
        ),
        main_path,
      ),
    )
    assert_true(
      is_some_path(
        tree_target("touch main.mbt", real_root, Some(real_root)),
        main_path,
      ),
    )
    assert_true(
      is_some_path(
        tree_target(
          "touch out.log 2>/dev/null || true",
          real_root,
          Some(real_root),
        ),
        main_path,
      ),
    )
    assert_true(
      tree_target("touch -h out.log", real_root, Some(real_root)) is None,
    )
    assert_true(
      tree_target("touch --no-dereference out.log", real_root, Some(real_root))
      is None,
    )
    assert_true(
      is_some_path(
        tree_target(
          "touch --no-dereference main.mbt",
          real_root,
          Some(real_root),
        ),
        main_path,
      ),
    )
    assert_true(
      is_some_path(
        tree_target(
          "printf x | tee main.mbt >/dev/null",
          real_root,
          Some(real_root),
        ),
        main_path,
      ),
    )
    assert_true(
      is_some_path(
        tree_target(
          "printf x | tee out.log >/dev/null",
          real_root,
          Some(real_root),
        ),
        main_path,
      ),
    )
    assert_true(
      is_some_path(
        tree_target(
          "install replacement.txt out.log",
          real_root,
          Some(real_root),
        ),
        main_path,
      ),
    )
    assert_true(
      is_some_path(
        tree_target(
          "install replacement.txt main.mbt",
          real_root,
          Some(real_root),
        ),
        main_path,
      ),
    )
    assert_true(
      is_some_path(
        tree_target(
          "install -Dm644 replacement.txt main.mbt",
          real_root,
          Some(real_root),
        ),
        main_path,
      ),
    )
    assert_true(
      is_some_path(
        tree_target(
          "install -Dm 644 replacement.txt main.mbt",
          real_root,
          Some(real_root),
        ),
        main_path,
      ),
    )
    assert_true(
      is_some_path(
        tree_target("Set-Content main.mbt value", real_root, Some(real_root)),
        main_path,
      ),
    )
    assert_true(
      is_some_path(
        tree_target(
          "Add-Content -Path out.log -Value value",
          real_root,
          Some(real_root),
        ),
        main_path,
      ),
    )
    assert_true(
      is_some_path(
        tree_target("Out-File -FilePath main.mbt", real_root, Some(real_root)),
        main_path,
      ),
    )
    assert_true(
      is_some_path(
        tree_target("Tee-Object -FilePath out.log", real_root, Some(real_root)),
        main_path,
      ),
    )
    assert_true(
      is_some_path(
        tree_target(
          "Copy-Item replacement.txt out.log",
          real_root,
          Some(real_root),
        ),
        main_path,
      ),
    )
    assert_true(
      is_some_path(
        tree_target(
          "Copy-Item _build/main.mbt src/main.mbt -ErrorAction SilentlyContinue",
          real_root,
          Some(real_root),
        ),
        "\{real_root}/src/main.mbt",
      ),
    )
    assert_true(
      is_some_path(
        tree_target("Move-Item main.mbt backup", real_root, Some(real_root)),
        main_path,
      ),
    )
    assert_true(
      is_some_path(
        tree_target("Remove-Item main.mbt", real_root, Some(real_root)),
        main_path,
      ),
    )
    assert_true(
      is_some_path(
        tree_target(
          "Rename-Item main.mbt backup.mbt",
          real_root,
          Some(real_root),
        ),
        main_path,
      ),
    )
    assert_true(
      is_some_path(
        tree_target(
          "New-Item -Path main.mbt -ItemType File",
          real_root,
          Some(real_root),
        ),
        main_path,
      ),
    )
    // `-Name` is the leaf created under `-Path`, so the target is `./main.mbt`,
    // not the `.` directory.
    assert_true(
      is_some_path(
        tree_target(
          "New-Item -Path . -Name main.mbt -ItemType File",
          real_root,
          Some(real_root),
        ),
        main_path,
      ),
    )
    let powershell_remove_glob = "Remove-Item *.mbt"
    assert_true(
      is_some_path(
        dyn_tree_target(powershell_remove_glob, real_root, Some(real_root)),
        real_root,
      ),
    )
    // Conservatively pre-blocked git: store feeders (external patch + plumbing),
    // mv, non-dry-run clean, reconfigured writers (-c filter / -C / --work-tree /
    // custom env), and checkout/restore forms that can clobber untracked source.
    for
      blocked_git in [
        "git apply patch.diff", "git am patch.mbox", "git apply --cached patch.diff",
        "git apply --index patch.diff", "git update-index --cacheinfo 100644,abc,main.mbt",
        "git read-tree HEAD", "git fast-import", "git mv notes.md main.mbt", "git clean -fd",
        "git clean -e -n -fd", "git -c filter.f.smudge=cmd checkout -- .", "git -C /tmp/x checkout -- .",
        "git checkout -f other", "git restore --source=HEAD~1 -- main.mbt", "GIT_DIR=/tmp/x git checkout -- main.mbt",
        "env GIT_WORK_TREE=. git restore main.mbt", "git checkout HEAD~1 -- main.mbt",
        "git restore -s HEAD~1 main.mbt", "git rebase -i main", "git rebase --exec ls main",
        "git rebase -s ours main", "git rebase --edit-todo", "git -c sequence.editor=x rebase --continue",
        "GIT_DIR=/tmp/x git rebase main", "git merge -s evil main", "git pull --rebase=interactive",
        "git cherry-pick --strategy=evil HEAD~1", "git bisect run ./test.sh", "git worktree move ../wt ../wt2",
        "git worktree remove --force ../wt",
        // submodule: foreach runs arbitrary commands; forced update/deinit lose data.
         "git submodule foreach echo hi", "git submodule --quiet foreach echo hi",
        "git submodule update --force", "git submodule deinit --force path", "git -c filter.f.smudge=cmd submodule update --init",
        "GIT_DIR=/tmp/x git submodule update --init",
      ] {
      assert_true(
        is_some_path(
          tree_target(blocked_git, real_root, Some(real_root)),
          real_root,
        ),
      )
    }
    // A store feeder is blocked unconditionally — not conditioned on the resolved
    // cwd — so it cannot slip through with a cwd outside the workspace (e.g. a
    // `git -C <workspace>` run from elsewhere).
    assert_true(
      tree_target(
        "git apply patch.diff",
        real_root,
        Some("\{real_root}-external"),
      )
      is Some(_),
    )
    // git apply is also caught in the TooComplex text path (e.g. globbed patches).
    let git_apply_glob = "git apply *.patch"
    assert_true(
      is_some_path(
        dyn_tree_target(git_apply_glob, real_root, Some(real_root)),
        real_root,
      ),
    )
    // A custom-env worktree writer is caught in the TooComplex text path too,
    // even though the env assignment precedes the `git` word.
    let git_env_glob = "GIT_DIR=/tmp/x git checkout -- *.mbt"
    assert_true(
      dyn_tree_target(git_env_glob, real_root, Some(real_root)) is Some(_),
    )
    // Recognized git porcelain (and dry-run clean) is not pre-blocked; worktree
    // writers run trusted and metadata commands remain harmlessly sandboxed.
    for
      allowed_git in [
        "git checkout -- .", "git checkout feature/foo", "git switch feature/foo",
        "git restore main.mbt", "git reset --hard", "git rm main.mbt", "git stash",
        "git clean -fdn", "git status", "git apply --check patch.diff", "git apply --stat patch.diff",
        "git worktree add ../wt", "git worktree remove ../wt", "git rebase main",
        "git rebase --continue", "git rebase --onto main feature~3 feature", "git rebase --rebase-merges main",
        // submodule: unforced update/deinit and non-writer verbs are not pre-blocked.
         "git submodule update --init", "git submodule --quiet update --init", "git submodule update --recursive",
        "git submodule deinit path", "git submodule add https://example.com/repo path",
        "git submodule set-url path url", "git submodule init", "git submodule sync",
        "git submodule status",
        // bare submodule is implicit status; foreach --help bypasses preblock.
         "git submodule", "git submodule --quiet", "git submodule foreach --help",
      ] {
      assert_true(tree_target(allowed_git, real_root, Some(real_root)) is None)
    }
    let find_sed_source = "find \{real_root} -name '*.mbt' -exec sed -i '' 's/42/43/' {} +"
    assert_true(
      is_some_path(
        dyn_tree_target(find_sed_source, real_root, Some(real_root)),
        real_root,
      ),
    )
    let find_env_sed_source = "find \{real_root} -name '*.mbt' -exec env FOO=bar sed -i '' 's/42/43/' {} + 2>/dev/null || true"
    assert_true(
      is_some_path(
        dyn_tree_target(find_env_sed_source, real_root, Some(real_root)),
        real_root,
      ),
    )
    let find_sed_source_case_insensitive = "find \{real_root} -iname '*.MBT' -exec sed -i '' 's/42/43/' {} +"
    assert_true(
      is_some_path(
        dyn_tree_target(
          find_sed_source_case_insensitive,
          real_root,
          Some(real_root),
        ),
        real_root,
      ),
    )
    let find_sed_readme_glob = "find \{real_root} -name README.* -exec sed -i '' 's/42/43/' '{}' +"
    assert_true(
      is_some_path(
        dyn_tree_target(find_sed_readme_glob, real_root, Some(real_root)),
        real_root,
      ),
    )
    // `xargs sed -i` runs sed as the xargs utility, so an in-place edit reached
    // that way must be blocked even though sed is not in shell command position.
    // (These shapes parse as TooComplex via the unquoted glob; the simple
    // `find ... | xargs sed -i` form parses as Simple and is caught by the
    // source-write sandbox instead.)
    let xargs_sed_source = "echo *.mbt | xargs sed -i '' 's/42/43/g'"
    assert_true(
      is_some_path(
        dyn_tree_target(xargs_sed_source, real_root, Some(real_root)),
        real_root,
      ),
    )
    let xargs_replace_sed = "echo *.mbt | xargs -I{} sed -i '' 's/42/43/g' {}"
    assert_true(
      is_some_path(
        dyn_tree_target(xargs_replace_sed, real_root, Some(real_root)),
        real_root,
      ),
    )
    let xargs_n1_sed = "echo *.mbt | xargs -n 1 sed -i '' 's/42/43/g'"
    assert_true(
      is_some_path(
        dyn_tree_target(xargs_n1_sed, real_root, Some(real_root)),
        real_root,
      ),
    )
    // BSD/macOS `-J replstr` consumes its operand before the utility.
    let xargs_bsd_replace_sed = "echo *.mbt | xargs -J {} sed -i '' 's/42/43/g' {}"
    assert_true(
      is_some_path(
        dyn_tree_target(xargs_bsd_replace_sed, real_root, Some(real_root)),
        real_root,
      ),
    )
    // The same xargs-utility gap still applies to `git apply` (the one blocked
    // git op); recognized porcelain is trusted or not pre-blocked.
    let xargs_git_apply = "echo *.patch | xargs git apply"
    assert_true(
      is_some_path(
        dyn_tree_target(xargs_git_apply, real_root, Some(real_root)),
        real_root,
      ),
    )
    // Read-only xargs pipelines (sed is not the xargs utility, no in-place edit)
    // must not be blocked, so analysis loops keep working.
    let xargs_grep_readonly = "echo *.mbt | xargs grep -l 'sed -i'"
    assert_true(
      dyn_tree_target(xargs_grep_readonly, real_root, Some(real_root)) is None,
    )
    let safe_find_then_sed = "find \{real_root} -name '*.txt' -print; sed -i '' 's/42/43/' *.mbt"
    assert_true(
      is_some_path(
        dyn_tree_target(safe_find_then_sed, real_root, Some(real_root)),
        real_root,
      ),
    )
    let env_wrapped_sed = "env FOO=bar sed -i '' 's/42/43/' *.mbt"
    assert_true(
      is_some_path(
        dyn_tree_target(env_wrapped_sed, real_root, Some(real_root)),
        real_root,
      ),
    )
    let env_assignment_sed = "FOO=bar sed -i '' 's/42/43/' *.mbt"
    assert_true(
      is_some_path(
        dyn_tree_target(env_assignment_sed, real_root, Some(real_root)),
        real_root,
      ),
    )
    let env_unset_wrapped_sed = "env -u FOO sed -i '' 's/42/43/' *.mbt"
    assert_true(
      is_some_path(
        dyn_tree_target(env_unset_wrapped_sed, real_root, Some(real_root)),
        real_root,
      ),
    )
    let env_long_unset_wrapped_sed = "env --unset FOO sed -i '' 's/42/43/' *.mbt"
    assert_true(
      is_some_path(
        dyn_tree_target(env_long_unset_wrapped_sed, real_root, Some(real_root)),
        real_root,
      ),
    )
    let command_wrapped_sed = "command sed -i '' 's/42/43/' *.mbt"
    assert_true(
      is_some_path(
        dyn_tree_target(command_wrapped_sed, real_root, Some(real_root)),
        real_root,
      ),
    )
    let find_sed_text = "find \{real_root} -name '*.txt' -exec sed -i '' 's/42/43/' {} +"
    assert_true(tree_target(find_sed_text, real_root, Some(real_root)) is None)
    assert_true(
      dyn_tree_target(find_sed_text, real_root, Some(real_root)) is None,
    )
    let find_sed_text_quoted = "find \{real_root} -name '*.txt' -exec sed -i '' 's/42/43/' '{}' +"
    assert_true(
      tree_target(find_sed_text_quoted, real_root, Some(real_root)) is None,
    )
    assert_true(
      dyn_tree_target(find_sed_text_quoted, real_root, Some(real_root)) is None,
    )
    let find_sed_filter_after_exec = "find \{real_root} -exec sed -i '' 's/42/43/' '{}' + -name '*.txt'"
    assert_true(
      is_some_path(
        tree_target(find_sed_filter_after_exec, real_root, Some(real_root)),
        real_root,
      ),
    )
    let broad_find_sed_text = "find \{real_root} -name '*' -exec sed -i '' 's/42/43/' '{}' +"
    assert_true(
      is_some_path(
        tree_target(broad_find_sed_text, real_root, Some(real_root)),
        real_root,
      ),
    )
    let find_sed_literal_source = "find \{real_root} -name '*.txt' -exec sed -i '' 's/42/43/' main.mbt ';'"
    assert_true(
      is_some_path(
        tree_target(find_sed_literal_source, real_root, Some(real_root)),
        real_root,
      ),
    )
    let find_sed_comma_quoted = "find \{real_root} -name '*.txt' -exec sed -i '' 's/42/43/' '{}' + , -exec sed -i '' 's/42/43/' '{}' +"
    assert_true(
      is_some_path(
        tree_target(find_sed_comma_quoted, real_root, Some(real_root)),
        real_root,
      ),
    )
    let readonly_sed_pipeline = "sed -n '1,5p' *.mbt | grep -i answer"
    assert_true(
      dyn_tree_target(readonly_sed_pipeline, real_root, Some(real_root)) is None,
    )
    let readonly_sed_file_named_i = "while true; do sed -f -i *.mbt\ndone"
    assert_true(
      dyn_tree_target(readonly_sed_file_named_i, real_root, Some(real_root))
      is None,
    )
    let multiline_sed = "while true; do printf ok\nsed -i '' 's/42/43/' *.mbt\ndone"
    assert_true(
      is_some_path(
        dyn_tree_target(multiline_sed, real_root, Some(real_root)),
        real_root,
      ),
    )
    let background_sed = "sleep 1 & sed -i '' 's/42/43/' *.mbt"
    assert_true(
      is_some_path(
        dyn_tree_target(background_sed, real_root, Some(real_root)),
        real_root,
      ),
    )
    let nested_shell_sed = "sh -c \"sed -i '' 's/42/43/' *.mbt\""
    assert_true(
      is_some_path(
        tree_target(nested_shell_sed, real_root, Some(real_root)),
        real_root,
      ),
    )
    let quoted_sed_text = "grep 'foo|sed -i' *.mbt"
    assert_true(
      dyn_tree_target(quoted_sed_text, real_root, Some(real_root)) is None,
    )
    let generated_script_with_sed = "cat > script.sh <<EOF\nsed -i 's/42/43/' f\nEOF"
    assert_true(
      dyn_tree_target(generated_script_with_sed, real_root, Some(real_root))
      is None,
    )
    let backslash_quoted_heredoc_then_copy = "cat <<\\EOF\nignored\nEOF\ncp main.mbt backup.mbt"
    assert_true(
      is_some_path(
        dyn_tree_target(
          backslash_quoted_heredoc_then_copy,
          real_root,
          Some(real_root),
        ),
        real_root,
      ),
    )
    let generated_script_then_executed = "cat > script.sh <<EOF\ncp main.mbt backup.mbt\nEOF\nsh script.sh"
    assert_true(
      is_some_path(
        dyn_tree_target(
          generated_script_then_executed,
          real_root,
          Some(real_root),
        ),
        real_root,
      ),
    )
    let tee_generated_script_then_executed = "tee script.sh <<EOF >/dev/null\ncp main.mbt backup.mbt\nEOF\nsh script.sh"
    assert_true(
      is_some_path(
        dyn_tree_target(
          tee_generated_script_then_executed,
          real_root,
          Some(real_root),
        ),
        real_root,
      ),
    )
    let pipe_tee_generated_script_then_executed = "cat <<EOF | tee script.sh >/dev/null\ncp main.mbt backup.mbt\nEOF\nsh script.sh"
    assert_true(
      is_some_path(
        dyn_tree_target(
          pipe_tee_generated_script_then_executed,
          real_root,
          Some(real_root),
        ),
        real_root,
      ),
    )
    let generated_script_then_bash_with_option = "cat > script.sh <<EOF\ncp main.mbt backup.mbt\nEOF\nbash -o pipefail script.sh"
    assert_true(
      is_some_path(
        dyn_tree_target(
          generated_script_then_bash_with_option,
          real_root,
          Some(real_root),
        ),
        real_root,
      ),
    )
    let generated_script_then_dot_sourced = "cat > script.sh <<EOF\ncp main.mbt backup.mbt\nEOF\n. script.sh"
    assert_true(
      is_some_path(
        dyn_tree_target(
          generated_script_then_dot_sourced,
          real_root,
          Some(real_root),
        ),
        real_root,
      ),
    )
    let generated_script_then_source_sourced = "cat > script.sh <<EOF\ncp main.mbt backup.mbt\nEOF\nsource script.sh"
    assert_true(
      is_some_path(
        dyn_tree_target(
          generated_script_then_source_sourced,
          real_root,
          Some(real_root),
        ),
        real_root,
      ),
    )
    let generated_script_then_shell_c_sourced = "cat > script.sh <<EOF\nmkdir -p _build/gen\ncp main.mbt _build/gen/main.mbt\nmv _build/gen pkg\nEOF\nsh -c '. ./script.sh'"
    assert_true(
      is_some_path(
        dyn_tree_target(
          generated_script_then_shell_c_sourced,
          real_root,
          Some(real_root),
        ),
        real_root,
      ),
    )
    let shell_heredoc_with_sed = "sh <<EOF\nsed -i '' 's/42/43/' *.mbt\nEOF"
    assert_true(
      is_some_path(
        dyn_tree_target(shell_heredoc_with_sed, real_root, Some(real_root)),
        real_root,
      ),
    )
    let python_heredoc_generated_move = "python3 <<EOF\nimport shutil\nshutil.move('_build/pkg', 'pkg')\nEOF"
    assert_true(
      is_some_path(
        dyn_tree_target(
          python_heredoc_generated_move,
          real_root,
          Some(real_root),
        ),
        real_root,
      ),
    )
    let heredoc_source_redirect = "cat 2>/dev/null > main.mbt <<'EOF' || true\npub fn answer() -> Int { 43 }\nEOF"
    assert_true(
      is_some_path(
        dyn_tree_target(heredoc_source_redirect, real_root, Some(real_root)),
        real_root,
      ),
    )
    let fd_duplicate_source_redirect = "printf x >& main.mbt *.txt 2>/dev/null || true"
    assert_true(
      is_some_path(
        dyn_tree_target(
          fd_duplicate_source_redirect,
          real_root,
          Some(real_root),
        ),
        real_root,
      ),
    )
    let rm_glob_source = "rm *.mbt 2>/dev/null || true"
    assert_true(
      is_some_path(
        dyn_tree_target(rm_glob_source, real_root, Some(real_root)),
        real_root,
      ),
    )
    let grep_mv_source = "grep mv *.mbt"
    assert_true(
      dyn_tree_target(grep_mv_source, real_root, Some(real_root)) is None,
    )
    let python_heredoc_source_write = "python3 - <<'PY'\nopen('main.mbt', 'w').write('pub fn answer() -> Int { 43 }\\n')\nPY"
    assert_true(
      is_some_path(
        dyn_tree_target(python_heredoc_source_write, real_root, Some(real_root)),
        main_path,
      ),
    )
    let outside_python_heredoc_source_write = "python3 - <<'PY'\nopen('/tmp/probe.mbt', 'w').write('x')\nPY"
    assert_true(
      dyn_tree_target(
        outside_python_heredoc_source_write,
        real_root,
        Some("/tmp"),
      )
      is None,
    )
    let outside_python_c_source_write = "python3 -c 'open(\"/tmp/probe.mbt\", \"w\").write(\"x\")' *.txt"
    assert_true(
      dyn_tree_target(outside_python_c_source_write, real_root, Some(real_root))
      is None,
    )
    let cd_outside_glob_sed = "cd /tmp && sed -i '' 's/42/43/' *.mbt"
    assert_true(
      dyn_tree_target(cd_outside_glob_sed, real_root, Some(real_root)) is None,
    )
    let cd_workspace_glob_sed = "cd \{real_root} && sed -i '' 's/42/43/' *.mbt"
    assert_true(
      is_some_path(
        dyn_tree_target(cd_workspace_glob_sed, real_root, Some("/tmp")),
        real_root,
      ),
    )
    let versioned_python_source_write = "python3.12 -c 'open(\"main.mbt\", \"w\").write(\"pub fn answer() -> Int { 43 }\\\\n\")'"
    assert_true(
      is_some_path(
        tree_target(versioned_python_source_write, real_root, Some(real_root)),
        main_path,
      ),
    )
    let python_exe_source_write = "Python.EXE -c 'open(\"main.mbt\", \"w+\").close()' 2>/dev/null || true"
    assert_true(
      is_some_path(
        tree_target(python_exe_source_write, real_root, Some(real_root)),
        main_path,
      ),
    )
    let python_create_mode_source_write = "python -c 'open(\"main.mbt\", \"x\").close()' 2>/dev/null || true"
    assert_true(
      is_some_path(
        tree_target(python_create_mode_source_write, real_root, Some(real_root)),
        main_path,
      ),
    )
    let masked_versioned_python_source_write = "python3.12 -c 'open(\"main.mbt\", \"w\").write(\"pub fn answer() -> Int { 43 }\\\\n\")' 2>/dev/null || true"
    assert_true(
      is_some_path(
        tree_target(
          masked_versioned_python_source_write,
          real_root,
          Some(real_root),
        ),
        main_path,
      ),
    )
    let find_sed_branch = "find \{real_root} -name '*.txt' -o -exec sed -i '' 's/42/43/' {} +"
    assert_true(
      is_some_path(
        dyn_tree_target(find_sed_branch, real_root, Some(real_root)),
        real_root,
      ),
    )
    let find_sed_branch_quoted = "find \{real_root} -name '*.txt' -o -exec sed -i '' 's/42/43/' '{}' +"
    assert_true(
      is_some_path(
        tree_target(find_sed_branch_quoted, real_root, Some(real_root)),
        real_root,
      ),
    )
    let find_sed_comma = "find \{real_root} -name '*.txt' -exec sed -i '' 's/42/43/' {} + , -exec sed -i '' 's/42/43/' {} +"
    assert_true(
      is_some_path(
        dyn_tree_target(find_sed_comma, real_root, Some(real_root)),
        real_root,
      ),
    )
    let grouped_sed = "{ sed -i '' 's/42/43/' *.mbt; }"
    assert_true(
      is_some_path(
        dyn_tree_target(grouped_sed, real_root, Some(real_root)),
        real_root,
      ),
    )
    let until_sed = "until sed -i '' 's/42/43/' *.mbt; do true; done"
    assert_true(
      is_some_path(
        dyn_tree_target(until_sed, real_root, Some(real_root)),
        real_root,
      ),
    )
    let elif_sed = "if false; then true; elif sed -i '' 's/42/43/' *.mbt; then true; fi"
    assert_true(
      is_some_path(
        dyn_tree_target(elif_sed, real_root, Some(real_root)),
        real_root,
      ),
    )
    let if_env_sed = "if env FOO=bar sed -i '' 's/42/43/' *.mbt; then true; fi"
    assert_true(
      is_some_path(
        dyn_tree_target(if_env_sed, real_root, Some(real_root)),
        real_root,
      ),
    )
    let if_command_sed = "if command sed -i '' 's/42/43/' *.mbt; then true; fi"
    assert_true(
      is_some_path(
        dyn_tree_target(if_command_sed, real_root, Some(real_root)),
        real_root,
      ),
    )
    let loop_sed = "while IFS= read -r f; do sed -i '' 's/42/43/' \"$f\"; done < /tmp/files.txt"
    assert_true(
      is_some_path(
        dyn_tree_target(loop_sed, real_root, Some(real_root)),
        real_root,
      ),
    )
    let cd_glob_sed = "cd pkg && sed -i '' 's/42/43/' *.mbt"
    assert_true(
      is_some_path(
        dyn_tree_target(cd_glob_sed, real_root, Some(real_root)),
        "\{real_root}/pkg",
      ),
    )
    let mkdir_or_cp_source = "mkdir gen || true; cp /tmp/generated.mbt gen 2>/dev/null || true"
    assert_true(
      is_some_path(
        tree_target(mkdir_or_cp_source, real_root, Some(real_root)),
        "\{real_root}/gen",
      ),
    )
    assert_true(
      is_some_path(
        tree_target(
          "cd src && mv pkg pkg.bak 2>/dev/null || true",
          real_root,
          Some(real_root),
        ),
        src_pkg_path,
      ),
    )
    assert_true(
      dyn_tree_target("cp main.mbt backup.txt", real_root, Some(real_root))
      is None,
    )
    assert_true(
      tree_target("cp main.mbt backup.txt", real_root, Some(real_root)) is None,
    )
    assert_true(
      is_some_path(
        tree_target("cp main.mbt backup.mbt", real_root, Some(real_root)),
        backup_path,
      ),
    )
    assert_true(
      is_some_path(
        tree_target("mv --force pkg pkg.bak", real_root, Some(real_root)),
        "\{real_root}/pkg",
      ),
    )
    assert_true(
      is_some_path(
        tree_target(
          "mv -b main.mbt backup 2>/dev/null || true",
          real_root,
          Some(real_root),
        ),
        main_path,
      ),
    )
    assert_true(
      is_some_path(
        tree_target(
          "mv --no-target-directory _build/gen pkg",
          real_root,
          Some(real_root),
        ),
        "\{real_root}/pkg",
      ),
    )
    assert_true(
      is_some_path(
        tree_target(
          "mkdir -p _build/gen.v1 && printf source > _build/gen.v1/main.mbt && mv _build/gen.v1 pkg.v1",
          real_root,
          Some(real_root),
        ),
        "\{real_root}/pkg.v1",
      ),
    )
    assert_true(
      is_some_path(
        tree_target(
          "mkdir -p assets _build/gen.tmp && printf source > _build/gen.tmp/main.mbt && mv _build/gen.tmp assets/pkg.tmp",
          real_root,
          Some(real_root),
        ),
        "\{real_root}/assets/pkg.tmp",
      ),
    )
    assert_true(
      tree_target(
        "mkdir -p assets _build && printf data > _build/logo.txt && mv _build/logo.txt assets/logo.txt",
        real_root,
        Some(real_root),
      )
      is None,
    )
  })
}

///|
#cfg(not(platform="windows"))
fn is_some_path(value : String?, expected : String) -> Bool {
  match value {
    Some(path) => path == expected
    None => false
  }
}

///|
async test "sandbox denial detection ignores masked exit code" {
  // Line-level classification pins live in `agent_tool/internal/sandbox`
  // (`denial_output_wbtest.mbt`); here only the shell-side gate is covered:
  // the denial fires despite exit_code 0, and only for a sandboxed command.
  @vfs.with_tmpdir(prefix="openseek-shell-denial-gate-", dir => {
    guard @sandbox.SandboxedCommand::create_if_available(dir, Shell(":"))
      is Some(command) else {
      return
    }
    let output = {
      exit_code: Some(0),
      text: "sh: main.mbt: Operation not permitted\n",
      output_limit_reached: false,
    }
    assert_true(
      agent_output_has_shell_sandbox_denial({
        output,
        sandboxed_command: Some(command),
      }),
    )
    assert_false(
      agent_output_has_shell_sandbox_denial({ output, sandboxed_command: None, }),
    )
    assert_false(
      agent_output_has_shell_sandbox_denial({
        output: {
          exit_code: Some(0),
          text: "Permission denied\n",
          output_limit_reached: false,
        },
        sandboxed_command: Some(command),
      }),
    )
  })
}

///|
#cfg(not(platform="windows"))
test "sandbox detects direct protected source write redirects" {
  let root = "/workspace"
  assert_true(
    redirect_target("printf x 2>/dev/null > main.mbt || true", root, Some(root))
    is Some("/workspace/main.mbt"),
  )
  assert_true(
    redirect_target("cd ./pkg && printf x > main.mbt", root, Some(root))
    is Some("/workspace/pkg/main.mbt"),
  )
  assert_true(
    redirect_target(
      "cd /missing 2>/dev/null || printf x 2>/dev/null > main.mbt || true",
      root,
      Some(root),
    )
    is Some("/workspace/main.mbt"),
  )
  assert_true(
    redirect_target(
      "cd /definitely-missing && :; printf x > main.mbt",
      root,
      Some(root),
    )
    is Some("/workspace/main.mbt"),
  )
  assert_true(
    redirect_target("cd /workspace; printf x > main.mbt", root, Some("/tmp"))
    is Some("/workspace/main.mbt"),
  )
  assert_true(
    redirect_target(
      "cd /workspace; cd ./pkg && printf x > main.mbt",
      root,
      Some("/tmp"),
    )
    is Some("/workspace/pkg/main.mbt"),
  )
  assert_true(
    redirect_target("cd ./pkg && true; printf x > main.mbt", root, Some(root))
    is Some("/workspace/pkg/main.mbt"),
  )
  assert_true(
    redirect_target("cd /tmp && printf x > main.mbt", root, Some(root)) is None,
  )
  assert_true(
    redirect_target("printf x > moon.work", root, Some(root))
    is Some("/workspace/moon.work"),
  )
  assert_true(
    redirect_target("printf x >| main.mbt", root, Some(root))
    is Some("/workspace/main.mbt"),
  )
  assert_true(
    redirect_target(": <> main.mbt", root, Some(root))
    is Some("/workspace/main.mbt"),
  )
  assert_true(
    redirect_target(": 4<> main.mbt", root, Some(root))
    is Some("/workspace/main.mbt"),
  )
  assert_true(
    redirect_target("printf x > _build/out", root, Some(root)) is None,
  )
  assert_true(
    redirect_target("printf x > _build/main.mbt", root, Some(root)) is None,
  )
  assert_true(
    redirect_target("printf x > .mooncakes/pkg/main.mbt", root, Some(root))
    is None,
  )
  assert_true(redirect_target("cat < main.mbt", root, Some(root)) is None)
  assert_true(
    redirect_target("printf x > /tmp/main.mbt", root, Some(root)) is None,
  )
}

///|
fn mode_for(cmd : String) -> SourceWriteMode {
  source_write_mode_for_parse(
    @shell_parse.parse_for_policy(cmd),
    "/workspace",
    Some("/workspace"),
  )
}

///|
/// `direct_source_tree_operation_target_for_root` on `cmd` parsed for policy.
async fn tree_target(cmd : String, root : String, cwd : String?) -> String? {
  direct_source_tree_operation_target_for_root(
    @shell_parse.parse_for_policy(cmd),
    root,
    cwd,
  )
}

///|
/// `dynamic_source_tree_operation_target` on `cmd` parsed for policy (the
/// underlying detector takes the parse and the raw text separately).
async fn dyn_tree_target(cmd : String, root : String, cwd : String?) -> String? {
  dynamic_source_tree_operation_target(
    @shell_parse.parse_for_policy(cmd),
    cmd,
    root,
    cwd,
  )
}

///|
/// `direct_source_write_redirect_target_for_root` on `cmd` parsed for policy.
#cfg(not(platform="windows"))
fn redirect_target(cmd : String, root : String, cwd : String?) -> String? {
  direct_source_write_redirect_target_for_root(
    @shell_parse.parse_for_policy(cmd),
    root,
    cwd,
  )
}

///|
test "sandbox trusts recognized porcelain and blocks dangerous forms" {
  // Recognized first-party porcelain that may write a worktree runs trusted.
  for
    cmd in [
      "git checkout -- main.mbt", "git checkout feature/foo", "git switch main",
      "git restore main.mbt", "git reset --hard", "git stash", "git stash pop", "git rm main.mbt",
      "git merge main", "git pull --rebase", "git cherry-pick HEAD~1", "git revert HEAD",
      "git clone https://example.com/repo", "git sparse-checkout set pkg", "git submodule update --init",
      "cd pkg && git checkout -- main.mbt",
    ] {
    assert_true(mode_for(cmd) is TrustedSourceWrite)
  }
  // External-patch/store-feeder git stays sandboxed, as do byte-moving `mv`,
  // destructive clean, explicit command runners, and external merge strategies.
  for
    cmd in [
      "git apply patch.diff", "git am patch.mbox", "git update-index --cacheinfo 100644,abc,main.mbt",
      "git read-tree HEAD", "git fast-import", "git mv notes.md main.mbt", "git clean -fd",
      "git bisect run ./test.sh", "git merge -s evil main", "git pull --rebase=interactive",
      "git worktree move ../wt ../wt2", "git worktree remove --force ../wt",
    ] {
    assert_true(mode_for(cmd) is SourceReadOnly)
  }
  // Reconfiguring global options (config/dir/exec/cwd/worktree) or a custom
  // environment could repoint git or enable a filter/merge driver, so they drop
  // git out of the trusted path.
  for
    cmd in [
      "git -c core.editor=x checkout -- .", "git -c filter.f.smudge=cmd checkout -- .",
      "git --git-dir=/tmp/x checkout -- .", "git --exec-path=/tmp checkout -- .",
      "git -C /tmp/x checkout -- .", "git --work-tree=/tmp/x checkout -- .", "FOO=bar git checkout -- .",
      "env GIT_CONFIG_COUNT=1 git checkout -- .",
    ] {
    assert_true(mode_for(cmd) is SourceReadOnly)
  }
  // Read/metadata porcelain does not need source-write trust on its own. Unknown
  // plumbing, aliases, and external command runners fail closed too.
  for cmd in ["git status", "git diff", "git checkout-index -a", "git co -- ."] {
    assert_true(mode_for(cmd) is SourceReadOnly)
  }
  // Recognized worktree verbs compose by default; destructive move/force-remove
  // forms were rejected above by the blocklist.
  for
    cmd in [
      "git worktree add ../wt", "git worktree add --force ../wt", "git worktree add -b feat ../wt HEAD",
      "git worktree add .worktrees/feature-x -b feature-x", "git worktree remove ../wt",
      "git worktree remove .worktrees/feature-x", "git worktree prune", "git worktree list",
    ] {
    assert_true(mode_for(cmd) is TrustedSourceWrite)
  }
  // A reconfigured or custom-environment invocation is demoted like any git.
  for
    cmd in [
      "git worktree remove --force ../wt", "git worktree remove -f ../wt", "git worktree remove --fo ../wt",
      "git worktree move ../wt ../wt2", "git -C /tmp/x worktree add ../wt", "GIT_DIR=/tmp/x git worktree add ../wt",
    ] {
    assert_true(mode_for(cmd) is SourceReadOnly)
  }
}

///|
test "recognized git chains compose while dangerous rebase stays sandboxed" {
  for
    cmd in [
      "git rebase", "git rebase main", "git rebase origin/main feature", "git rebase --onto main feature~3 feature",
      "git rebase --keep-base main", "git rebase --autostash main", "git rebase --fork-point main",
      "git rebase --continue", "git rebase --abort", "git rebase --skip", "git rebase --quit",
      "git rebase --rebase-merges main", "git rebase --root", "git rebase --cont",
      "cd pkg && git rebase --continue", "git fetch origin main && git rebase origin/main 2>&1",
      "cd /workspace && git fetch origin main && git rebase origin/main 2>&1",
    ] {
    assert_true(mode_for(cmd) is TrustedSourceWrite)
  }
  // Explicit command-running forms and reconfigured/custom-environment rebases
  // still fail closed.
  for
    cmd in [
      "git rebase -i main", "git rebase --exec ls main", "git rebase -s ours main",
      "git -c sequence.editor=x rebase main", "git -C /tmp/x rebase --abort", "FOO=bar git rebase main",
      "env GIT_DIR=/tmp/x git rebase --continue",
    ] {
    assert_true(mode_for(cmd) is SourceReadOnly)
  }
}

///|
async test "sandbox scans source writes after CRLF here-documents" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-crlf-heredoc-", root => {
    @fs.write_file(
      "\{root}/main.mbt",
      "pub fn answer() -> Int { 42 }\n",
      create_mode=CreateOrTruncate,
    )
    let real_root = @fs.realpath(root)
    // CRLF line endings must not break here-document terminator matching. The
    // unquoted marker read used to keep the trailing `\r` while the closing-line
    // match stripped it, so the body never terminated and swallowed the later
    // in-place source edit.
    let crlf_heredoc_then_sed = "cat <<EOF\r\nnote\r\nEOF\r\nsed -i 's/42/43/' main.mbt\r\n"
    assert_true(
      dyn_tree_target(crlf_heredoc_then_sed, real_root, Some(real_root))
      is Some(_),
    )
    // The LF form already worked; keep it as a control for the same shape.
    let lf_heredoc_then_sed = "cat <<EOF\nnote\nEOF\nsed -i 's/42/43/' main.mbt\n"
    assert_true(
      dyn_tree_target(lf_heredoc_then_sed, real_root, Some(real_root))
      is Some(_),
    )
  })
}

///|
async test "sandbox scans source writes after arithmetic left shifts" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-arith-shift-", root => {
    @fs.write_file(
      "\{root}/main.mbt",
      "pub fn answer() -> Int { 42 }\n",
      create_mode=CreateOrTruncate,
    )
    let real_root = @fs.realpath(root)
    // `$((1 << 8))` is arithmetic, not a here-document; the `<<` left shift must
    // not be read as a here-document operator whose phantom delimiter hides the
    // following in-place source edit.
    let arith_then_sed = "SHIFT=$((1 << 8))\nsed -i 's/42/43/' main.mbt\n"
    assert_true(
      dyn_tree_target(arith_then_sed, real_root, Some(real_root)) is Some(_),
    )
    // A bare arithmetic command with no source write stays allowed.
    let arith_only = "echo $((1 << 8))\n"
    assert_true(dyn_tree_target(arith_only, real_root, Some(real_root)) is None)
  })
}

///|
async test "moon new is a trusted scaffold only for a new or empty target" {
  @vfs.with_tmpdir(prefix="moon-new-scaffold-", root => {
    // a genuinely new target: nothing to overwrite -> safe (stays trusted)
    assert_false(
      parse_scaffolds_unsafe_target(
        @shell_parse.parse_for_policy("moon new \{root}/fresh"),
        root,
      ),
    )
    // an existing EMPTY directory -> still safe
    @fs.mkdir("\{root}/emptydir")
    assert_false(
      parse_scaffolds_unsafe_target(
        @shell_parse.parse_for_policy("moon new \{root}/emptydir"),
        root,
      ),
    )
    // an existing NON-EMPTY directory (loose source) -> UNSAFE: moon new could
    // overwrite it, so this must fall back to the source-write sandbox
    @fs.mkdir("\{root}/pkg")
    @fs.write_file(
      "\{root}/pkg/main.mbt",
      "fn main {  }\n",
      create_mode=CreateOrTruncate,
    )
    assert_true(
      parse_scaffolds_unsafe_target(
        @shell_parse.parse_for_policy("moon new \{root}/pkg"),
        root,
      ),
    )
    // The same non-empty target expressed relative to the command cwd must be
    // classified the same way.
    assert_true(
      parse_scaffolds_unsafe_target(
        @shell_parse.parse_for_policy("moon new pkg"),
        root,
      ),
    )
    // no target at all -> undeterminable -> treated as unsafe
    assert_true(
      parse_scaffolds_unsafe_target(
        @shell_parse.parse_for_policy("moon new"),
        root,
      ),
    )
    // a non-scaffold command is never an unsafe scaffold
    assert_false(
      parse_scaffolds_unsafe_target(
        @shell_parse.parse_for_policy("moon fmt"),
        root,
      ),
    )
  })
}

///|
/// The scratch-lab backstop (K3 review): with a lab present, a "trusted"
/// source-writing moon command (e.g. `moon new`) that would otherwise
/// launch UNSANDBOXED is forced onto the sandboxed profile — so the kernel,
/// not just the static guard, denies any workspace-source write. Without a
/// lab the same command stays trusted/unsandboxed.
async test "a scratch lab forces trusted source-writes onto the sandbox" {
  let ws = @fs.tmpdir(prefix="openseek-lab-ws-")
  guard @sandbox.SandboxedCommand::create_if_available(ws, Shell(":"))
    is Some(_) else {
    println("sandbox-exec unavailable; skipping")
    @fs.rmdir(ws, recursive=true) catch {
      _ => ()
    }
    return
  }
  let lab = @fs.tmpdir(prefix="openseek-lab-scratch-")
  // No lab: `moon new` in the lab is the trusted, unsandboxed path.
  let without = agent_shell_launch(
    ws,
    "moon new \{lab}/probe",
    @shell_parse.parse_for_policy("moon new \{lab}/probe"),
    cwd=lab,
  )
  assert_true(without.sandboxed_command is None)
  // With the lab wired, the same command is sandboxed instead — the
  // profile allows lab writes, the kernel denies workspace writes.
  let with_lab = agent_shell_launch(
    ws,
    "moon new \{lab}/probe",
    @shell_parse.parse_for_policy("moon new \{lab}/probe"),
    cwd=lab,
    scratch_dir=lab,
  )
  assert_true(with_lab.sandboxed_command is Some(_))
  @fs.rmdir(ws, recursive=true)
  @fs.rmdir(lab, recursive=true)
}

///|
/// The K3 backstop above must hold through the WIRED entry
/// (`execute_with_workspace`), not just `agent_shell_launch`: `shell`'s
/// launch call sites must forward `scratch_dir`, or a lab child's trusted
/// scaffold runs unsandboxed and the lexical guard is the sole defense
/// again. The probe is the K3 escape itself: `moon new` through an in-lab
/// symlink pointing at the workspace — admitted lexically, denied only by
/// the kernel, so workspace survival is the assertion that carries the
/// test.
async test "the lab kernel backstop holds through the wired shell entry" {
  let ws_raw = @fs.tmpdir(prefix="openseek-lab-e2e-ws-")
  guard @sandbox.SandboxedCommand::create_if_available(ws_raw, Shell(":"))
    is Some(_) else {
    println("sandbox-exec unavailable; skipping")
    @fs.rmdir(ws_raw, recursive=true) catch {
      _ => ()
    }
    return
  }
  let ws = @fs.realpath(ws_raw)
  let lab = @fs.realpath(@fs.tmpdir(prefix="openseek-lab-e2e-lab-"))
  @fs.symlink(target=ws, "\{lab}/link")
  let escape = execute_with_workspace(
    ws,
    { "cmd": "moon new \{lab}/link/probe" },
    read_only=true,
    default_timeout_ms=30_000,
    scratch_dir=lab,
  )
  guard escape is Respond(escape_output) else {
    fail("expected Respond for the escape probe")
  }
  // The kernel, not the guard, stops the escape: nothing reaches the
  // workspace through the symlink.
  assert_true(escape_output.is_error)
  assert_false(@fs.exists("\{ws}/probe/moon.mod"))
  // The same lab stays genuinely usable through the wired path (the
  // sandboxed profile does not over-block honest in-lab scaffolds).
  let honest = execute_with_workspace(
    ws,
    { "cmd": "moon new \{lab}/probe2" },
    read_only=true,
    default_timeout_ms=30_000,
    scratch_dir=lab,
  )
  guard honest is Respond(honest_output) else {
    fail("expected Respond for the in-lab probe")
  }
  assert_false(honest_output.is_error)
  assert_true(@fs.exists("\{lab}/probe2/moon.mod"))
  @fs.rmdir(ws, recursive=true) catch {
    _ => ()
  }
  @fs.rmdir(lab, recursive=true) catch {
    _ => ()
  }
}

///|
/// The background branch shares the same obligation: `run_in_background`
/// must forward the lab into `start_background`, so the job launches with
/// the sandboxed profile (visible on its snapshot) and the kernel denies
/// the symlink escape there too.
#cfg(not(platform="windows"))
async test "the lab kernel backstop holds through the background job path" {
  let ws_raw = @fs.tmpdir(prefix="openseek-lab-bg-ws-")
  guard @sandbox.SandboxedCommand::create_if_available(ws_raw, Shell(":"))
    is Some(_) else {
    println("sandbox-exec unavailable; skipping")
    @fs.rmdir(ws_raw, recursive=true) catch {
      _ => ()
    }
    return
  }
  let ws = @fs.realpath(ws_raw)
  let lab = @fs.realpath(@fs.tmpdir(prefix="openseek-lab-bg-lab-"))
  @fs.symlink(target=ws, "\{lab}/link")
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime(AgentTaskScope(group))
    let action = execute_with_workspace(
      ws,
      { "cmd": "moon new \{lab}/link/probe", "run_in_background": true },
      read_only=true,
      bg_runtime=bg,
      scratch_dir=lab,
    )
    guard action is Respond(started) else {
      fail("expected Respond for the background start")
    }
    assert_false(started.is_error)
    let jobs = bg.list()
    assert_eq(jobs.length(), 1)
    // The launch itself carries the sandbox — the direct pin that
    // `start_background` received the lab.
    assert_true(jobs[0].sandboxed_command is Some(_))
    assert_true(bg.wait_exit(jobs[0].id, 30_000))
    assert_false(@fs.exists("\{ws}/probe/moon.mod"))
  })
  @fs.rmdir(ws, recursive=true) catch {
    _ => ()
  }
  @fs.rmdir(lab, recursive=true) catch {
    _ => ()
  }
}

///|
test "a file path needs a non-empty alphabetic extension to look non-source" {
  assert_true(looks_like_non_source_file_path("notes/readme.txt"))
  assert_true(looks_like_non_source_file_path("archive.tar"))
  // A trailing dot leaves an empty extension, which is not an extension.
  assert_false(looks_like_non_source_file_path("weird."))
  // No dot at all, and digits or symbols in place of an extension.
  assert_false(looks_like_non_source_file_path("Makefile"))
  assert_false(looks_like_non_source_file_path("archive.tar.7z"))
  // Protected MoonBit sources stay source-looking however they are spelled.
  assert_false(looks_like_non_source_file_path("lib/parser.mbt"))
}

///|
/// `mv`/`cp` with a single operand names a source and no destination, so there
/// is no tree transfer to point at. The two-operand forms are covered above;
/// this pins the boundary between them, which is what tells the last operand
/// apart from the only operand.
async test "a lone operand is a source with no destination" {
  @vfs.with_tmpdir(prefix="openseek-shell-lone-operand-", root => {
    @fs.mkdir("\{root}/pkg")
    let real_root = @fs.realpath(root)
    assert_true(tree_target("mv pkg", real_root, Some(real_root)) is None)
    assert_true(tree_target("cp pkg", real_root, Some(real_root)) is None)
    assert_true(tree_target("mv -f pkg", real_root, Some(real_root)) is None)
  })
}

///|
/// Unsandboxed setup helper for worker-mode fixtures: run git, require success.
async fn worker_git_setup(args : Array[String], cwd : String) -> String {
  let (code, data) = @process.collect_stdout(
    "git",
    args,
    inherit_env=true,
    cwd=cwd.view(),
  )
  guard code == 0 else { fail("git failed in \{cwd}: \{data.text()}") }
  data.text()
}

///|
/// Worker mode through the WIRED shell entry: every class — including a
/// trusted git verb — launches under the worker profile, so origin writes,
/// shared-store writes, and worktree surgery are kernel-denied while the
/// worker's own tree stays writable. Mirrors the lab regression tests: the
/// call sites, not `agent_shell_launch`, are what these pin.
async test "worker mode confines the wired shell to the worker tree" {
  @vfs.with_tmpdir(prefix="openseek-worker-mode-", dir => {
    guard @sandbox.SandboxedCommand::create_if_available(dir, Shell(":"))
      is Some(_) else {
      println("sandbox-exec unavailable; skipping")
      return
    }
    let repo = "\{dir}/repo"
    @fs.mkdir(repo)
    let _ = worker_git_setup(["init", "-q"], repo)
    let _ = worker_git_setup(["config", "user.email", "e2e@test"], repo)
    let _ = worker_git_setup(["config", "user.name", "e2e"], repo)
    @vfs.write_text(repo, "seed.txt", "seed\n")
    let _ = worker_git_setup(["add", "-A"], repo)
    let _ = worker_git_setup(["commit", "-q", "-m", "base"], repo)
    let _ = worker_git_setup(
      ["worktree", "add", "-q", ".worktrees/w1", "-b", "w1"],
      repo,
    )
    let origin = @fs.realpath(repo)
    let worker_root = @fs.realpath("\{repo}/.worktrees/w1")
    let admin_raw = worker_git_setup(
      ["rev-parse", "--absolute-git-dir"],
      worker_root,
    )
    let scope : WorkerSandbox = {
      deny_roots: [@fs.realpath("\{origin}/.git"), origin],
      worker_root,
      worker_admin_dir: @fs.realpath(admin_raw.trim().to_owned()),
    }
    async fn run(cmd : String) -> @agent_tool.ToolAction {
      execute_with_workspace(
        worker_root,
        { "cmd": cmd },
        read_only=false,
        default_timeout_ms=30_000,
        worker_sandbox=scope,
      )
    }
    // The worker's own tree is writable through the tool.
    guard run("printf x > \{worker_root}/scratch.txt") is Respond(own) else {
      fail("expected Respond")
    }
    assert_false(own.is_error)
    assert_true(@fs.exists("\{worker_root}/scratch.txt"))
    // An absolute-path write into the origin is kernel-denied; the seed
    // survives (the assertion that carries the test).
    guard run("printf x > \{origin}/seed.txt") is Respond(against_origin) else {
      fail("expected Respond")
    }
    assert_true(against_origin.is_error)
    assert_eq(@fs.read_file("\{origin}/seed.txt").text(), "seed\n")
    // A TRUSTED verb is forced onto the sandbox: `git worktree add` would run
    // unsandboxed in a normal registry, but here its origin write is denied.
    guard run("git worktree add \{origin}/evil-wt -b evil") is Respond(surgery) else {
      fail("expected Respond")
    }
    assert_true(surgery.is_error)
    assert_false(@fs.exists("\{origin}/evil-wt"))
    // Reads of git state keep working.
    guard run("git status --porcelain") is Respond(status) else {
      fail("expected Respond")
    }
    assert_false(status.is_error)
  })
}
