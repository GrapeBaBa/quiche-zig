# quiche-zig

Zig bindings to [quiche](https://github.com/cloudflare/quiche) — Cloudflare's
QUIC + HTTP/3 implementation. A single `quiche` module exposes both quiche's C
API and the bundled BoringSSL headers (`SSL_*`, `EVP_*`, ...). The static library
contains BoringSSL inlined, so no separate ssl/crypto link step is needed.

Currently builds quiche `0.28.0` from the upstream crate.

## Requirements

- Zig 0.16+
- A Rust toolchain (`cargo`) on `PATH`. For cross-compiling, install the
  matching `rustup target`.

## Use

In your `build.zig`:

```zig
const dep = b.dependency("quiche", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("quiche", dep.module("quiche"));
```

In Zig source:

```zig
const std = @import("std");
const quiche = @import("quiche");

pub fn main() void {
    std.debug.print("quiche {s}\n", .{quiche.quiche_version()});
}
```
