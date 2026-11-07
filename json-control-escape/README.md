# Json.to_string leaves control characters unescaped

`Json.to_string` (stdlib/json.march, `escape_of`) escapes only `"`, `\`, `\b`, `\t`, `\n`, `\f` and `\r`.
Every other code point in U+0000-U+001F (e.g. BEL U+0007, VT U+000B, U+001F) is written raw.
RFC 8259 §7 requires all of them to be escaped, so strict parsers reject the output:
node's `JSON.parse` says `Bad control character in string literal`, Python's `json.loads` says `Invalid control character`.

Found while porting a game that sends LLM chat history as JSON: a single U+000B pasted from Word made every later request a 400.

Run: `./run.sh` (march main b7c963d74). Expected: `"a\u0007b\u000bc\u001f"`. Actual: the raw bytes, `REPRODUCED`.

Suggested fix: in `escape_of`, return `\u00XX` for any `c < 32` not already handled.
