// The signed-in account's Cloud skill library. Replies reuse the host's skill
// protocol so the Skills page treats both libraries alike: a request the
// service refuses becomes the reply's error, carrying the service's message,
// while sign-in, transport and decoding failures raise `RequestError`.

///|
/// One skills request. 400, 404, 409 and 502 carry a message for the person
/// acting; any other failure raises.
async fn skills_request(
  path : String,
  method_ : @http.RequestMethod,
  token~ : String,
  body? : Json,
) -> Result[Json?, String] {
  let headers : Map[@http.CaseInsensitiveString, String] = {
    "Content-Type": "application/json",
    "Authorization": "Bearer \{token}",
  }
  let (response, data) = @http.request(
    CloudOrigin + path,
    method_,
    headers,
    body.map_or("", body => body.stringify()),
  ) catch {
    _ => raise RequestError(Unreachable)
  }
  match response.code {
    200 => Ok(Some(data.json() catch { _ => raise RequestError(Malformed) }))
    204 => Ok(None)
    400 | 404 | 409 | 502 => {
      let message = data.text() catch { _ => "" }
      guard !message.trim().is_empty() else {
        raise RequestError(Http(response.code))
      }
      Err(message.trim().to_owned())
    }
    code => {
      // 401 expires the sign-in; anything else is an unexpected status.
      check_status(code)
      raise RequestError(Http(code))
    }
  }
}

///|
fn[T : @json.FromJson] decode(json : Json?) -> T raise RequestError {
  guard json is Some(json) else { raise RequestError(Malformed) }
  @json.from_json(json) catch {
    _ => raise RequestError(Malformed)
  }
}

///|
fn skill_path(id : String) -> String {
  "/v1/me/skills/\{@uri.encode_component(id)}"
}

///|
/// The Mooncakes registry's catalog, as the service lists it.
pub async fn skills_catalog(token : String) -> @protocol.SkillsCatalogReply {
  match skills_request("/v1/skills/catalog", Get, token~) {
    Ok(json) => decode(json)
    Err(message) => SkillsCatalogError(message)
  }
}

///|
/// A registry release's SKILL.md.
pub async fn skills_content(
  token : String,
  payload : @protocol.InstallSkillPayload,
) -> @protocol.SkillContentReply {
  guard payload.module_name.split("/").collect() is [owner, name] else {
    return SkillContentError("invalid skill reference")
  }
  let path = "/v1/skills/catalog/\{@uri.encode_component(owner)}/\{@uri.encode_component(name)}?version=\{@uri.encode_component(payload.version)}"
  match skills_request(path, Get, token~) {
    Ok(json) => decode(json)
    Err(message) => SkillContentError(message)
  }
}

///|
/// The account's library: always-on built-ins and installs, enabled or not.
pub async fn skills_installed(token : String) -> @protocol.InstalledSkillsReply {
  match skills_request("/v1/me/skills", Get, token~) {
    Ok(Some({ "skills": skills, .. })) =>
      InstalledSkills(decode(Some(skills)), builtin_errors=[])
    Ok(_) => raise RequestError(Malformed)
    Err(message) => InstalledSkillsError(message)
  }
}

///|
/// An installed skill's SKILL.md.
pub async fn skills_installed_content(
  token : String,
  id : String,
) -> @protocol.SkillContentReply {
  match skills_request("\{skill_path(id)}/content", Get, token~) {
    Ok(json) => decode(json)
    Err(message) => SkillContentError(message)
  }
}

///|
/// Install a registry release, or update an installed skill to it.
pub async fn skills_install(
  token : String,
  payload : @protocol.InstallSkillPayload,
) -> @protocol.InstallSkillReply {
  let body : Json = {
    "module_name": payload.module_name,
    "version": payload.version,
  }
  match skills_request("/v1/me/skills", Post, token~, body~) {
    Ok(json) => SkillInstalled(decode(json))
    Err(message) => SkillInstallError(message)
  }
}

///|
pub async fn skills_uninstall(
  token : String,
  id : String,
) -> @protocol.UninstallSkillReply {
  match skills_request(skill_path(id), Delete, token~) {
    Ok(None) => SkillUninstalled
    Ok(Some(_)) => raise RequestError(Malformed)
    Err(message) => SkillUninstallError(message)
  }
}

///|
pub async fn skills_set_enabled(
  token : String,
  payload : @protocol.SetSkillEnabledPayload,
) -> @protocol.SetSkillEnabledReply {
  let body : Json = { "enabled": payload.enabled }
  match skills_request(skill_path(payload.id), Patch, token~, body~) {
    Ok(json) => {
      let _ : @protocol.InstalledSkill = decode(json)
      SkillEnabledSet
    }
    Err(message) => SkillEnabledError(message)
  }
}
