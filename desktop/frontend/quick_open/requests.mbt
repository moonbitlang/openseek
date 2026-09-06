// Host transport for the palette's two providers. Every function here returns
// a Cmd; the state machine decides when one is armed and which reply is still
// current.

///|
/// Populating warms a cache session for a root without asking for rows;
/// querying reads bounded top-K rows out of the warmed session.
priv enum FileRequestKind {
  PopulateCache
  QueryCache
}

///|
/// Search files inside one cache session and route the reply back to the exact
/// owning run. A request whose root does not belong to the owner's channel is
/// dropped: the palette opened before placement resolved, and the restart on
/// the arriving root will ask again.
fn file_request(
  emit : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  root~ : @common.Uri?,
  cache_key : String,
  query : String,
  generation : Int,
  kind : FileRequestKind,
) -> @cmd.Cmd {
  guard root is Some(root) && @resource.belongs_to(root, owner.channel) else {
    return @cmd.none
  }
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        owner.channel,
        @commands.fs_search_files,
        {
          path: root.path,
          cache_key,
          query,
          max_results: match kind {
            PopulateCache => 0
            QueryCache => MaxFileResults
          },
          generation,
        },
      ) catch {
        _ => {
          scheduler.add(
            emit(
              match kind {
                PopulateCache =>
                  FileCacheRequestFailed(owner~, cache_key~, generation~)
                QueryCache =>
                  FilesRequestFailed(owner~, cache_key~, query~, generation~)
              },
            ),
          )
          return
        }
      }
      if reply.cancelled {
        return
      }
      match kind {
        PopulateCache =>
          scheduler.add(emit(FileCacheLoaded(owner~, cache_key~, generation~)))
        QueryCache => {
          let files = [
            for path in reply.files if !path.is_empty() => @pathx.Relative(path)
          ]
          scheduler.add(
            emit(
              FilesLoaded(
                owner~,
                cache_key~,
                query~,
                generation~,
                files~,
                from_cache=reply.from_cache,
                limit_hit=reply.limit_hit,
              ),
            ),
          )
        }
      }
    })
  })
}

///|
/// Abandon the in-flight query for one cache session. The Host answers the
/// abandoned request with `cancelled`, which the reply path drops.
fn cancel_file_search(
  owner : @interop.ConversationKey,
  cache_key : String,
  generation : Int,
) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    @js.async_run(() => {
      ignore(
        @interop.bridge_request(
          owner.channel,
          @commands.fs_cancel_search_files,
          { cache_key, generation, },
        ),
      ) catch {
        _ => ()
      }
    })
  })
}

///|
/// Release a cache session the palette will never read again.
fn clear_file_cache(
  owner : @interop.ConversationKey,
  cache_key : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    @js.async_run(() => {
      ignore(
        @interop.bridge_request(
          owner.channel,
          @commands.fs_clear_file_search_cache,
          { cache_key, },
        ),
      ) catch {
        _ => ()
      }
    })
  })
}

///|
/// Search workspace symbols and route the reply back to the exact owning run.
fn symbol_request(
  emit : @cmd.Emit[Msg],
  root : @common.Uri?,
  owner : @interop.ConversationKey,
  query : String,
  generation : Int,
) -> @cmd.Cmd {
  guard root is Some(root) && @resource.belongs_to(root, owner.channel) else {
    return @cmd.none
  }
  @symbols.search(
    owner,
    query,
    root~,
    loaded=items => emit(SymbolsLoaded(owner~, query~, generation~, items~)),
    failed=emit(SymbolsRequestFailed(owner~, query~, generation~)),
  )
}
