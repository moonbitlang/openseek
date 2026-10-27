// `ssh_model_credentials` lives in `exports.mbt`: its consumer is the window
// host (`desktop/app/internal/extension/extension.mbt`), a sibling module with
// its own `moon.work`, so `moon ide analyze` cannot see the use and that block
// is exported on purpose there.
