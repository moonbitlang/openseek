///|
/// Unlike the composer's optional PR decoration, an explicit GitHub request
/// must preserve CLI/auth/network failures so the panel can offer a retry.
async fn github_command(
  gh : @pathx.Absolute,
  dir : @pathx.Absolute,
  args : Array[String],
) -> String {
  let (code, stdout, stderr) = @processx.collect_output_no_stdin(
    gh.0,
    args,
    cwd=dir.0,
    extra_env=git_environment(),
    inherit_env=false,
  ) catch {
    error => raise HostError("Could not run GitHub CLI: \{error}")
  }
  guard code == 0 else {
    let detail = stderr.text() catch {
      _ => "GitHub CLI returned unreadable error output."
    }
    raise HostError(
      if detail.trim().is_empty() {
        "GitHub CLI failed (exit \{code})."
      } else {
        detail.trim().to_owned()
      },
    )
  }
  stdout.text() catch {
    _ => raise HostError("GitHub CLI returned unreadable output.")
  }
}

///|
async fn github_panel_json(
  gh : @pathx.Absolute,
  dir : @pathx.Absolute,
  args : Array[String],
) -> Json {
  let output = github_command(gh, dir, args)
  @json.parse(output) catch {
    _ => raise HostError("GitHub CLI returned invalid JSON.")
  }
}

///|
fn github_list_args(
  kind : @protocol.GithubListKind,
  repository_url : String,
  limit : Int,
) -> Array[String] {
  let args = [
    if kind is Issues {
      "issue"
    } else {
      "pr"
    },
    "list",
    "--repo",
    repository_url,
    "--state",
    "open",
    "--limit",
    (limit + 1).to_string(),
    "--json",
    if kind is Issues {
      "number,title,url,author"
    } else {
      "number,title,url,author,isDraft"
    },
  ]
  if kind is CreatedByMe {
    args.append(["--author", "@me"])
  }
  args
}

///|
fn github_panel_item(
  raw : Json,
  kind : @protocol.GithubListKind,
  avatars : Map[String, String],
) -> @protocol.GithubItem raise {
  guard raw
    is {
      "number": number,
      "title": String(title),
      "url": String(url),
      "author": author,
      ..
    } else {
    raise HostError("GitHub returned an invalid list item.")
  }
  let number : Int = @json.from_json(number)
  guard number > 0 && !url.is_empty() else {
    raise HostError("GitHub returned an invalid item identity.")
  }
  let author = match author {
    Null => None
    { "login": String(login), .. } => Some(login)
    _ => raise HostError("GitHub returned an invalid author.")
  }
  let draft = if kind is Issues {
    false
  } else {
    match raw {
      { "isDraft": True, .. } => true
      { "isDraft": False, .. } => false
      _ =>
        raise HostError("GitHub returned an invalid pull request draft state.")
    }
  }
  {
    number,
    title,
    url,
    author,
    avatar_url: author.bind(login => avatars.get(login)),
    draft,
  }
}

///|
/// gh's list JSON includes author node IDs but omits avatarUrl. Resolve the
/// distinct authors in batches through GitHub's Actor interface; never invent
/// avatar URLs from logins, particularly for bots and enterprise accounts.
async fn github_avatar_urls(
  repository_url : String,
  items : Array[Json],
  query : async (Array[String]) -> Json,
) -> Map[String, String] {
  let avatars : Map[String, String] = Map([])
  guard repository_url.strip_prefix("https://") is Some(rest) &&
    rest.split("/").next() is Some(host) else {
    raise HostError("GitHub returned an invalid repository URL.")
  }
  let ids : Array[String] = []
  for item in items {
    if item is { "author": { "id": String(id), .. }, .. } && !ids.contains(id) {
      ids.push(id)
    }
  }
  for offset = 0; offset < ids.length(); offset = offset + 100 {
    let args = [
      "api",
      "graphql",
      "--hostname",
      host.to_owned(),
      "-f",
      "query=query($ids:[ID!]!){nodes(ids:$ids){... on Actor{login avatarUrl(size:32)}}}",
    ]
    for index in offset..<(offset + 100).min(ids.length()) {
      args.append(["-f", "ids[]=\{ids[index]}"])
    }
    let result = query(args)
    guard result is { "data": { "nodes": Array(nodes), .. }, .. } else {
      raise HostError("GitHub returned invalid avatar metadata.")
    }
    for node in nodes {
      match node {
        Null => ()
        { "login": String(login), "avatarUrl": String(url), .. } if url.has_prefix(
            "https://",
          ) => avatars[login] = url
        _ => raise HostError("GitHub returned invalid avatar metadata.")
      }
    }
  }
  avatars
}

///|
async fn github_list_op(
  payload : @protocol.GithubListPayload,
) -> @protocol.GithubListReply {
  guard payload.limit > 0 && payload.limit <= 1000 else {
    raise HostError("GitHub list size must be between 1 and 1000.")
  }
  guard @pathx.Absolute::from_uri_path(payload.cwd) is Some(dir) else {
    raise HostError("Select a workspace with an absolute checkout path.")
  }
  guard resolve_gh() is Some(gh) else {
    raise HostError(
      "Install GitHub CLI (gh) and run gh auth login to load pull requests and issues.",
    )
  }
  github_list(payload, args => github_panel_json(gh, dir, args))
}

///|
async fn github_list(
  payload : @protocol.GithubListPayload,
  query : async (Array[String]) -> Json,
  inventory_timeout? : Int = 20000,
  avatar_timeout? : Int = 5000,
) -> @protocol.GithubListReply {
  let inventory = @async.with_timeout_opt(inventory_timeout, () => {
    // Keep repository resolution in gh: it understands enterprise hosts,
    // default remotes and fork parents. Pin the subsequent list to that URL.
    let repository = query(["repo", "view", "--json", "nameWithOwner,url"])
    guard repository
      is { "nameWithOwner": String(name), "url": String(url), .. } else {
      raise HostError("GitHub returned invalid repository metadata.")
    }
    let listing = query(github_list_args(payload.kind, url, payload.limit))
    guard listing is Array(raw_items) else {
      raise HostError("GitHub returned an invalid list.")
    }
    (name, url, raw_items)
  })
  guard inventory is Some((name, url, raw_items)) else {
    raise HostError(
      "GitHub request timed out. Check your connection and retry.",
    )
  }
  // End the inventory deadline before optional metadata work. A timeout or
  // lookup error preserves the list and travels separately from absent avatars.
  let (avatars, avatar_error) = try {
    match
      @async.with_timeout_opt(avatar_timeout, () => {
        github_avatar_urls(url, raw_items, query)
      }) {
      Some(avatars) => (avatars, None)
      None => (Map([]), Some("GitHub avatar request timed out."))
    }
  } catch {
    error => (Map([]), Some("Could not load GitHub avatars: \{error}"))
  }
  let items : Array[@protocol.GithubItem] = []
  for raw in raw_items.iter().take(payload.limit) {
    items.push(github_panel_item(raw, payload.kind, avatars))
  }
  {
    repository: name,
    repository_url: url,
    items,
    has_more: raw_items.length() > payload.limit,
    avatar_error,
  }
}
