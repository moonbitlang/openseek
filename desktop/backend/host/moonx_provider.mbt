///|
fn HostState::moonx_provider(self : HostState) -> @moonbit.MoonxProvider {
  MoonxProvider(
    engine=self.engine,
    runtime_dir=self.runtime_dir,
    source=self.resources.moonbit,
  )
}
