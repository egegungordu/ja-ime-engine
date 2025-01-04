const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Modules
    // romaji_parser
    const romaji_parser = b.addModule("romaji_parser", .{
        .root_source_file = b.path("src/romaji_parser.zig"),
        .target = target,
        .optimize = optimize,
    });

    _ = romaji_parser;
}
