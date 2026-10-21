///|
priv suberror CloudDownloadError {
  CloudDownloadError(String)
}

///|
fn require_download_account(
  account : () -> @protocol.AccountSession?,
  expected : @protocol.AccountSession,
) -> Unit raise CloudDownloadError {
  guard account() is Some(current) &&
    current.user.user_id == expected.user.user_id &&
    current.token == expected.token else {
    raise CloudDownloadError(
      "The account changed. Download the file again after signing in.",
    )
  }
}

///|
/// Claim a destination atomically, including against concurrent downloads.
/// A failed or cancelled write removes only the file this operation created.
async fn save_download(
  directory : String,
  name : String,
  write : async (@fs.File) -> Unit,
) -> String {
  let extension = @pathx.Path(name).extname().to_owned()
  let stem = name.strip_suffix(extension).unwrap_or(name.view()).to_owned()
  for index = 0; ; index = index + 1 {
    let name = if index == 0 { name } else { "\{stem} (\{index})\{extension}" }
    let path = @pathx.Path(directory).join(Relative(name)).to_string()
    let output = @fs.open(path, mode=WriteOnly, create_mode=CreateNew) catch {
      @os_error.OSError(_) as error if error.is_EEXIST() => continue index + 1
      error => raise error
    }
    let mut complete = false
    defer {
      output.close()
      if !complete {
        @fs.remove(path) catch {
          _ => ()
        }
      }
    }
    write(output)
    complete = true
    return path
  }
}

///|
/// A window-only operation: credentials come from the current native account,
/// never another host or a token supplied by the renderer. Original downloads
/// stream straight to Downloads without a second cache or a renderer-sized copy.
async fn download_cloud_file(
  payload : @protocol.CloudFileDownloadPayload,
  account : () -> @protocol.AccountSession?,
  directory : String,
  origin~ : String = @protocol.CloudOrigin,
  reveal~ : async (String) -> Int32 = @platform.reveal_path,
) -> @protocol.CloudFileDownloadReply {
  try {
    guard account() is Some(current) && current.user.user_id == payload.account else {
      raise CloudDownloadError(
        "Sign in to the file's account before downloading.",
      )
    }
    let parts = payload.path.split("/").to_array()
    guard !parts.is_empty() &&
      !payload.path.contains("\\") &&
      !payload.path.contains("\u0000") &&
      parts.all(part => !part.is_empty() && part != "." && part != "..") else {
      raise CloudDownloadError(
        "Download requires a workspace-relative file path.",
      )
    }
    let name = parts[parts.length() - 1].to_owned()
    let base = "\{origin}/v1/sessions/\{@uri.encode_component(payload.session)}/files/"
    let encoded = @uri.encode_component(payload.path)
    let headers : Map[@http.CaseInsensitiveString, String] = {
      "Authorization": "Bearer " + current.token,
      "Accept-Encoding": "identity",
    }
    let cached = match payload.cached {
      Some(cached) if !cached.etag.is_empty() => {
        let bytes = @base64.decode(cached.data_base64) catch {
          _ => raise CloudDownloadError("Invalid cached file bytes.")
        }
        let validation = headers.copy()
        validation["If-None-Match"] = cached.etag
        let (response, _) = @http.request(
          base + "content?path=" + encoded + "&allow_large=true",
          Head,
          validation,
          "",
        )
        if response.code == 304 {
          Some(bytes)
        } else {
          check_download_status(response.code)
          None
        }
      }
      _ => None
    }
    require_download_account(account, current)
    let path = match cached {
      Some(bytes) =>
        save_download(directory, name, output => {
          require_download_account(account, current)
          output.write(bytes)
          require_download_account(account, current)
        })
      None => {
        let (response, client) = @http.get_stream(
          base + "download?path=" + encoded,
          headers~,
        )
        defer client.close()
        check_download_status(response.code)
        require_download_account(account, current)
        save_download(directory, name, output => {
          while client.read_some(max_len=256 * 1024) is Some(chunk) {
            require_download_account(account, current)
            output.write(chunk)
          }
          require_download_account(account, current)
        })
      }
    }
    let revealed = try {
      require_download_account(account, current)
      reveal(path) == 0
    } catch {
      _ => false
    }
    Saved(path~, revealed~)
  } catch {
    CloudDownloadError(message) => Failed(message~)
    error => Failed(message="Could not download the file: \{error}")
  }
}

///|
fn check_download_status(status : Int32) -> Unit raise CloudDownloadError {
  if status == 401 {
    raise CloudDownloadError(
      "Your account sign-in expired. Sign in again to download the file.",
    )
  }
  guard status == 200 else {
    raise CloudDownloadError("Cloud API returned HTTP \{status}.")
  }
}
