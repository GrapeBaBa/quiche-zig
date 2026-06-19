const std = @import("std");

/// Locates the boringssl include dir in a hash-named cargo OUT_DIR (LazyPath can't
/// glob a hash known only after cargo runs) and symlinks it into a stable dir for translate-c.
/// argv: <cargo-build-dir> <output-include-dir>
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 3) {
        std.log.err("usage: stage-boringssl <cargo-build-dir> <output-dir>", .{});
        return error.InvalidArgs;
    }

    const cwd = std.Io.Dir.cwd();
    var target = try cwd.openDir(io, args[1], .{ .iterate = true });
    defer target.close(io);

    // cargo leaves stale boring-sys-<hash> dirs co-existing and its OUT_DIR layout
    // isn't contractual, so re-derive the path and pick the newest-mtime match (the live one).
    var inc_rel: ?[]const u8 = null;
    var inc_mtime: i96 = std.math.minInt(i96);
    {
        var w = try target.walk(gpa);
        defer w.deinit();
        while (try w.next(io)) |e| {
            if (e.kind != .directory or
                std.mem.indexOf(u8, e.path, "boring-sys-") == null or
                !std.mem.endsWith(u8, e.path, "out/boringssl/src/include")) continue;
            const stat = try target.statFile(io, e.path, .{});
            if (inc_rel != null and stat.mtime.nanoseconds <= inc_mtime) continue;
            inc_rel = try arena.dupe(u8, e.path);
            inc_mtime = stat.mtime.nanoseconds;
        }
    }
    const rel = inc_rel orelse {
        std.log.err("boringssl include dir (boring-sys-*/out/boringssl/src/include) not found under {s}", .{args[1]});
        return error.BoringSslIncludeNotFound;
    };

    // Symlink each top-level entry into the output dir; absolute targets resolve from any cwd.
    const inc_abs = try target.realPathFileAlloc(io, rel, gpa);
    defer gpa.free(inc_abs);

    var inc = try target.openDir(io, rel, .{ .iterate = true });
    defer inc.close(io);
    var out = try cwd.openDir(io, args[2], .{});
    defer out.close(io);

    var it = inc.iterate();
    while (try it.next(io)) |e| {
        const link_target = try std.fs.path.join(gpa, &.{ inc_abs, e.name });
        defer gpa.free(link_target);
        // The output dir isn't cleared between runs; deleteTree unlinks the symlink itself (not its target) so the recreate is idempotent.
        try out.deleteTree(io, e.name);
        try out.symLink(io, link_target, e.name, .{ .is_directory = e.kind == .directory });
    }
}
