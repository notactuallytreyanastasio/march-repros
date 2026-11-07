# `x +. 0.0` keeps a negative zero on native and JS

IEEE 754 says `-0.0 + 0.0` and `0.0 + -0.0` are `+0.0`. The interpreter gets that right. Native and JS builds return `-0.0` for both. The value comes from `string_to_float("-0.0")` at run time, so this isn't constant folding of literals: compiled code seems to simplify `x +. 0.0` and `0.0 +. x` to `x`. The JS build here has `--disable-pass opt.fold` and still does it.

```
== interpreter
m: -0 (want -0)
0.0 +. m: +0 (IEEE: +0)
m +. 0.0: +0 (IEEE: +0)
== native
0.0 +. m: -0 (IEEE: +0)
m +. 0.0: -0 (IEEE: +0)
== js (opt.fold disabled)
0.0 +. m: -0 (IEEE: +0)
m +. 0.0: -0 (IEEE: +0)
```

The sign of a zero is visible through `atan2`, `1.0 /. x` (on JS) and float bit patterns. We found it while matching a Swift audio synth bit for bit. (`x *. 1.0` and `x -. 0.0` are safe identities; `x +. 0.0` is not.)

Run `./run.sh`; the last line is `REPRODUCED` or `NOT REPRODUCED`.
