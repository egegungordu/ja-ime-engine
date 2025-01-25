const std = @import("std");

const tools = @import("tools/build.zig");
const tests = @import("tests/build.zig");
const wasm = @import("wasm/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Private modules

    const mod_datastructs = b.createModule(.{
        .root_source_file = b.path("src/datastructs/datastructs.zig"),
        .target = target,
        .optimize = optimize,
    });
    const mod_utf8utils = b.createModule(.{
        .root_source_file = b.path("src/utf8utils/utf8utils.zig"),
        .target = target,
        .optimize = optimize,
    });
    const mod_core = b.createModule(.{
        .root_source_file = b.path("src/core/core.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "datastructs", .module = mod_datastructs },
            .{ .name = "utf8utils", .module = mod_utf8utils },
        },
    });

    // Dictionary serializer tool

    const dict_path = tools.build(b, .{
        .src_dir = "tools",
        .imports = &.{
            .{ .name = "datastructs", .module = mod_datastructs },
            .{ .name = "core", .module = mod_core },
        },
    });

    // Public (exported) modules

    // kana
    const mod_kana = b.addModule("kana", .{
        .root_source_file = b.path("src/kana.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core", .module = mod_core },
        },
    });

    // ime-core
    _ = b.addModule("ime_core", .{
        .root_source_file = b.path("src/ime_core.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core", .module = mod_core },
        },
    });

    // ime-ipadic
    const ime_ipadic = b.addModule("ime_ipadic", .{
        .root_source_file = b.path("src/ime_ipadic.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "core", .module = mod_core },
        },
    });
    ime_ipadic.addAnonymousImport("ipadic", .{ .root_source_file = dict_path });

    // WASM lib

    wasm.build(b, .{
        .src_dir = "wasm",
        .imports = &.{
            .{ .name = "core", .module = mod_core },
        },
    });

    // Tests

    tests.build(b, .{
        .src_dir = "tests",
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "datastructs", .module = mod_datastructs },
            .{ .name = "core", .module = mod_core },
            .{ .name = "utf8utils", .module = mod_utf8utils },
            .{ .name = "kana", .module = mod_kana },
        },
    });
}
