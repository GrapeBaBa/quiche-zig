const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const quiche_dep = b.dependency("quiche", .{});

    const release = optimize != .Debug;
    const profile_dir = if (release) "release" else "debug";
    const rust_triple = rustTarget(b, target.result);

    const cargo = b.addSystemCommand(&.{
        "cargo",
        "build",
        // Without --quiet, cargo's "Compiling ..." progress messages go to stderr,
        // which Zig's Run step treats as diagnostic output and reports under a
        // misleading "failed command:" header (even though cargo exited cleanly).
        "--quiet",
        "--features",
        "ffi",
        "--target",
        rust_triple,
    });
    if (release) cargo.addArg("--release");
    cargo.addArg("--target-dir");
    cargo.setCwd(quiche_dep.path("."));
    const cargo_target = cargo.addOutputDirectoryArg("target");

    const lib_subpath = b.fmt("{s}/{s}/libquiche.a", .{ rust_triple, profile_dir });
    const libquiche = cargo_target.path(b, lib_subpath);

    const translate = b.addTranslateC(.{
        .root_source_file = b.path("src/quiche.h"),
        .target = target,
        .optimize = optimize,
    });
    translate.addIncludePath(quiche_dep.path("include"));
    translate.addIncludePath(quiche_dep.path("deps/boringssl/src/include"));
    const quiche_mod = translate.addModule("quiche");
    // libquiche.a has no C++ stdlib usage, but Rust's std references the Itanium-ABI
    // unwinder (rust_eh_personality, _Unwind_*); link_libcpp pulls libunwind transitively.
    quiche_mod.link_libcpp = true;
    quiche_mod.addObjectFile(libquiche);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("quiche", quiche_mod);

    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Build and run quiche-zig binding tests");
    test_step.dependOn(&run_unit_tests.step);
}

fn rustTarget(b: *std.Build, t: std.Target) []const u8 {
    const arch = switch (t.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "aarch64",
        .x86 => "i686",
        .arm => "arm",
        .riscv64 => "riscv64gc",
        else => std.debug.panic("no rust triple mapping for arch {s}", .{@tagName(t.cpu.arch)}),
    };
    return switch (t.os.tag) {
        .linux => if (t.abi.isMusl())
            b.fmt("{s}-unknown-linux-musl", .{arch})
        else
            b.fmt("{s}-unknown-linux-gnu", .{arch}),
        .macos => b.fmt("{s}-apple-darwin", .{arch}),
        .windows => if (t.abi == .gnu)
            b.fmt("{s}-pc-windows-gnu", .{arch})
        else
            b.fmt("{s}-pc-windows-msvc", .{arch}),
        else => std.debug.panic("no rust triple mapping for os {s}", .{@tagName(t.os.tag)}),
    };
}
