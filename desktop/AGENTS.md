# Desktop Agent Notes

## Frontend And Host Compatibility

- The desktop frontend and host are versioned and shipped together. Do not
  support a current frontend talking to an older desktop host.
- Evolve desktop protocol payloads, the frontend, and the host in lockstep. Do
  not make fields optional, hide controls, or add capability detection solely
  for compatibility with a pre-change host unless the user explicitly asks for
  it.
