// HTTP adapters for the shared loopback browser login.

///|
/// The user the demo signs in as.
let demo_user : Json = {
  "user_id": "demo",
  "login": "demo-user",
  "avatar_url": "",
}

///|
/// The demo's account, as the relay's account exchange answers it.
let demo_account : Json = { "token": "demo", "user": demo_user }

///|
async fn Proxy::begin_sign_in(
  self : Proxy,
  req : @moonback.Request,
  res : @moonback.Responder,
) -> Unit {
  let return_to = req.query().get("return_to")
  if self.upstream is Demo {
    send_page(
      res,
      @moonback.Html::raw(
        @browser_signin.sign_in_markup(
          demo_account.stringify(),
          return_to=return_to.unwrap_or("/cloud"),
        ),
      ),
    )
    return
  }
  let location = self.sign_in.begin(return_to) catch {
    error => {
      send_page(res, failure_page("\{error}"), status=500)
      return
    }
  }
  res.send_void(status=302, headers={ "Location": location })
}

///|
async fn Proxy::finish_sign_in(
  self : Proxy,
  req : @moonback.Request,
  res : @moonback.Responder,
) -> Unit {
  let query = req.query()
  match
    self.sign_in.finish(
      query.get("state"),
      query.get("code"),
      query.get("error"),
    ) {
    Ok(html) => send_page(res, @moonback.Html::raw(html))
    Err((status, message)) => send_page(res, failure_page(message), status~)
  }
}

///|
/// A document explaining why sign-in stopped, with a way back.
fn failure_page(message : String) -> @moonback.Html {
  Html(async fn(builder) {
    builder.write_string(
      "<!doctype html><meta charset=\"utf-8\"><title>Sign-in failed</title><p>",
    )
    @moonback.Html::escape(message).write_to(builder)
    builder.write_string(
      "</p><p><a href=\"/cloud\">Back to the console</a></p>",
    )
  })
}

///|
async fn send_page(
  res : @moonback.Responder,
  page : @moonback.Html,
  status~ : Int32 = 200,
) -> Unit {
  res.send_html(page, status~, headers={ "Cache-Control": "no-store" })
}
