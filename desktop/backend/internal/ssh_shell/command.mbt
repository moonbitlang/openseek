///|
fn double_quote(value : String) -> String {
  "\"" +
  value
  .replace_all(old="\\", new="\\\\")
  .replace_all(old="\"", new="\\\"")
  .replace_all(old="$", new="\\$")
  .replace_all(old="`", new="\\`") +
  "\""
}

///|
/// Load the working user's login environment, then execute a POSIX payload.
/// Base64 carries arbitrary UTF-8 without shell-specific quote concatenation.
/// Neither bootstrap nor decoding consumes stdin: it belongs to the protocol
/// or upload. Keep the outer program on one line and free of single quotes;
/// csh rejects quoted newlines, nu rejects adjacent quote fragments, and xonsh
/// expands escapes and environment references even inside single quotes.
pub fn command(payload : String) -> String {
  let decoder =
    #|payload=$(printf %s "$1" | /usr/bin/base64 -d; printf .); unset OPENSEEK_SSH_PAYLOAD OPENSEEK_SSH_DECODE; exec /bin/sh -c "${payload%.}"
  let enter =
    #|exec /bin/sh -c "$OPENSEEK_SSH_DECODE" sh "$OPENSEEK_SSH_PAYLOAD"
  let csh = "set loginsh=1; if ( -r /etc/csh.login ) source /etc/csh.login; if ( -r ~/.login ) source ~/.login; " +
    enter
  let nu =
    #|exec /bin/sh -c $env.OPENSEEK_SSH_DECODE sh $env.OPENSEEK_SSH_PAYLOAD
  let script = [
    "if [ -z \"${SHELL:-}\" ] || [ ! -x \"$SHELL\" ]; then echo \"SeekMoon SSH requires SHELL to name an executable login shell\" >&2; exit 127; fi;",
    "OPENSEEK_SSH_PAYLOAD=\"$1\"; OPENSEEK_SSH_DECODE=" +
    double_quote(decoder) +
    "; export OPENSEEK_SSH_PAYLOAD OPENSEEK_SSH_DECODE;",
    "case \"${SHELL##*/}\" in",
    "csh|tcsh) exec \"$SHELL\" -i -c " + double_quote(csh) + " ;;",
    "nu) exec \"$SHELL\" -l -i -c " + double_quote(nu) + " ;;",
    "*) exec \"$SHELL\" -l -i -c " + double_quote(enter) + " ;;",
    "esac",
  ].join(" ")
  let encoded = @base64.encode(@utf8.encode(payload))
  let inner = "/bin/sh -c '" + script + "' sh '" + encoded + "'"
  let program = @base64.encode(@utf8.encode(inner))
  "/bin/sh -c 'test -x /usr/bin/base64 || { echo \"SeekMoon SSH requires /usr/bin/base64\" >&2; exit 127; }; exec /bin/sh -c \"`printf %s " +
  program +
  " | /usr/bin/base64 -d`\"'"
}
