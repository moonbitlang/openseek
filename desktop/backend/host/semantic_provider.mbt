///|
fn HostState::semantic_provider(self : HostState) -> @search.SemanticProvider? {
  self.resources.moongrep.map(command => {
    @search.semantic_provider(
      command,
      engine=self.engine,
      runtime_dir=self.runtime_dir,
      source=self.resources.moonbit,
    )
  })
}
