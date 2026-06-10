///|
/// Configuration of one file-edit eval run: DeepSeek access (`api_key`,
/// `model`), trial shape (`runs`, `concurrency`, `min_successes`,
/// `max_steps`), artifact and workspace locations (`out_dir`, `repo_root`),
/// and the prompt variant under test (`prompt_label`,
/// `system_prompt_file`, `system_prompt_addendum_file` — empty paths mean
/// the built-in prompt). The cases themselves come from the sibling `cases`
/// package.
pub struct Config {
  api_key : String
  model : @deepseek.Model
  runs : Int
  concurrency : Int
  min_successes : Int
  max_steps : Int
  out_dir : String
  repo_root : String
  prompt_label : String
  system_prompt_file : String
  system_prompt_addendum_file : String
}

///|
/// Build a config; every field is explicit because eval runs must be
/// reproducible from their recorded parameters alone.
pub fn Config::Config(
  api_key~ : String,
  model~ : @deepseek.Model,
  runs~ : Int,
  concurrency~ : Int,
  min_successes~ : Int,
  max_steps~ : Int,
  out_dir~ : String,
  repo_root~ : String,
  prompt_label~ : String,
  system_prompt_file~ : String,
  system_prompt_addendum_file~ : String,
) -> Config {
  {
    api_key,
    model,
    runs,
    concurrency,
    min_successes,
    max_steps,
    out_dir,
    repo_root,
    prompt_label,
    system_prompt_file,
    system_prompt_addendum_file,
  }
}
