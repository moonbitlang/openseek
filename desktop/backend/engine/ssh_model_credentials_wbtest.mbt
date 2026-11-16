///|
async test "SSH forwards only the selected local provider credential" {
  with_settings_dir((_, manager) => {
    defer @sys.unset_env_var("DEEPSEEK")
    defer @sys.unset_env_var("GLM")
    assert_true(ssh_model_credentials(manager).is_empty())
    @sys.set_env_var("DEEPSEEK", "ambient-deepseek")
    @sys.set_env_var("GLM", "ambient-glm")
    assert_eq(ssh_model_credentials(manager), { "DEEPSEEK": "ambient-deepseek" })
    for
      (provider, name, key) in [
        ("deepseek", "DEEPSEEK", "stored-deepseek"),
        ("glm", "GLM", "stored-glm"),
      ] {
      ignore(
        update_settings(manager, {
          provider: Some(provider),
          providers: Some({
            "deepseek": { api_url: None, api_key: Some("stored-deepseek"), },
            "glm": { api_url: None, api_key: Some("stored-glm"), },
          }),
        }),
      )
      assert_eq(ssh_model_credentials(manager), Map([(name, key)]))
    }
  })
}

///|
async test "SSH custom keys follow the model family without forwarding endpoint settings" {
  with_settings_dir((_, manager) => {
    let previous = @sys.get_env_var("OPENSEEK_MODEL")
    defer (match previous {
      Some(value) => @sys.set_env_var("OPENSEEK_MODEL", value)
      None => @sys.unset_env_var("OPENSEEK_MODEL")
    })
    ignore(
      update_settings(manager, {
        provider: Some("custom"),
        providers: Some({
          "custom": {
            api_url: Some("https://custom.example/chat/completions"),
            api_key: Some("custom-key"),
          },
        }),
      }),
    )
    for
      (model, name) in [
        ("deepseek-flash", "DEEPSEEK"),
        ("kimi-k2.7-code", "KIMI"),
        ("glm-5.3", "GLM"),
      ] {
      @sys.set_env_var("OPENSEEK_MODEL", model)
      assert_eq(ssh_model_credentials(manager), Map([(name, "custom-key")]))
    }
    ignore(
      update_settings(manager, {
        provider: None,
        providers: Some({ "custom": { api_url: None, api_key: Some(""), } }),
      }),
    )
    assert_true(ssh_model_credentials(manager).is_empty())
  })
}
