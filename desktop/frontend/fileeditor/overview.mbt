///|
/// The Cloud overview and Changes tab describe the same repository snapshot.
/// The history snapshot names the checked-out branch and its actual HEAD.
/// The changes inventory may compare the working tree to an earlier base.
pub fn State::overview_changes(
  self : State,
  locale : @i18n.Locale,
) -> @conversation_overview.Changes {
  {
    summary: match self.git_graph {
      GitGraphReady(repository=true, ..) =>
        git_graph_branch_label(locale~, self)
      _ => ""
    },
    rows: () => {
      if self.changes is ChangeListReady(repository=false, ..) {
        return [@html.span(ui(locale, GitUnavailable))]
      }
      let rows : Array[@html.Html] = []
      match self.git_graph {
        GitGraphReady(repository=true, snapshot~, ..) => {
          if snapshot.branch is Some(branch) {
            rows.push(
              @html.div(class="conv-overview-row", title=branch, [
                @icons.icon(@icons.icon_git_branch),
                @html.span(class="conv-overview-row-text", branch),
              ]),
            )
          }
          if snapshot.head is Some(head) {
            rows.push(
              @html.div(class="conv-overview-row", title=head, [
                @html.span(class="conv-overview-row-sub", "HEAD"),
                @html.span(class="conv-overview-command", short_commit(head)),
              ]),
            )
          } else {
            rows.push(@html.span(ui(locale, NoCommits)))
          }
        }
        GitGraphFailed(error) =>
          if self.changes != ChangeListFailed(error) {
            rows.push(@html.span(error))
          }
        GitGraphIdle | GitGraphLoading =>
          rows.push(@html.span(ui(locale, LoadingHistory)))
        GitGraphReady(..) => ()
      }
      match self.changes {
        ChangeListReady(files~, ..) =>
          if files.is_empty() {
            rows.push(@html.span(ui(locale, NoChangedFiles)))
          } else {
            for file in files {
              rows.push(
                @html.div(class="conv-overview-row", title=file.path.0, [
                  @html.span(class="conv-overview-row-sub", file.status_label()),
                  @html.span(class="conv-overview-row-text", file.path.0),
                ]),
              )
            }
          }
        ChangeListFailed(error) => rows.push(@html.span(error))
        ChangeListIdle | ChangeListLoading(..) =>
          rows.push(@html.span(ui(locale, LoadingChangedFiles)))
      }
      rows
    },
  }
}
