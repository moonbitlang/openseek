///|
fn HostState::semantic_provider(self : HostState) -> @search.SemanticProvider {
  SemanticProvider(
    engine=self.engine,
    runtime_dir=self.runtime_dir,
    source=self.resources.moonbit,
  )
}
