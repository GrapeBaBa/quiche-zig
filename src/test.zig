const std = @import("std");
const quiche = @import("quiche");

test "quiche and BoringSSL bindings link" {
    try std.testing.expectEqual(@as(c_int, 20), quiche.QUICHE_MAX_CONN_ID_LEN);

    const ctx = quiche.SSL_CTX_new(quiche.TLS_method()) orelse return error.OpenSSLFailed;
    defer quiche.SSL_CTX_free(ctx);

    const config = quiche.quiche_config_new(quiche.QUICHE_PROTOCOL_VERSION) orelse return error.QuicheConfigFailed;
    defer quiche.quiche_config_free(config);

    try std.testing.expect(std.mem.len(quiche.quiche_version()) > 0);
}
