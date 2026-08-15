# Desktop Agent Notes

## Frontend And Host Compatibility

- The desktop frontend and host are versioned and shipped together. Do not
  support a current frontend talking to an older desktop host.
- Evolve desktop protocol payloads, the frontend, and the host in lockstep. Do
  not make fields optional, hide controls, or add capability detection solely
  for compatibility with a pre-change host unless the user explicitly asks for
  it.

## Desktop Trust And Security Model

- A frontend connected and authenticated to a Desktop instance is trusted with
  the authority of the local user. This includes the Proton renderer, an
  authenticated relay frontend, and code the user runs in that frontend's
  DevTools.
- The connected frontend can already invoke Desktop terminal and shell
  operations. Letting the same frontend select a working directory or send an
  app-server execution-policy field is therefore not, by itself, a privilege
  escalation or a Desktop security-boundary violation.
- The security boundary is before a frontend obtains an authenticated Desktop
  command channel. Unauthenticated network peers, unrelated web origins,
  repository content, model output, and other displayed data are not trusted
  principals and must not acquire command authority merely by being processed
  or rendered.
- Continue validating command payloads for type safety, protocol correctness,
  product invariants, and protection against accidental destructive actions.
  Workspace and path checks may enforce product scope, but they do not sandbox
  a trusted frontend that can already spawn a shell.
- Prefer typed request and response models at Desktop command boundaries. They
  document the protocol, reject malformed data, and expose schema drift during
  development; do not justify them as a privilege boundary against the trusted
  frontend.
- A security finding must name the less-trusted principal and the new capability
  it gains. Do not report a privilege escalation solely because a trusted
  frontend can craft fields that the normal UI does not expose.
