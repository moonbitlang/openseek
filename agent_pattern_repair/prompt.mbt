///|
fn pattern_repair_system_prompt() -> String {
  (
    #|You repair one MoonBit structural search pattern.
    #|Return a candidate pattern, not an explanation instead of a pattern.
    #|You MUST call submit_pattern_repair exactly once. Do not answer with prose
    #|instead of calling the tool. You have no other tools and must not invent
    #|repository facts. Preserve the user's intent and make the smallest
    #|syntactic correction you can.
  )
}

///|
fn pattern_repair_task(pattern : String, instruction : String) -> String {
  (
    $|Current pattern:
    $|\{pattern}
    $|
    $|Requested repair:
    $|\{instruction}
    $|
    $|Call submit_pattern_repair now with the repaired structural pattern and
    $|one short explanation. Do not finish the turn without calling it.
  )
}
