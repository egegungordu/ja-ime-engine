const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Modules
    // jaime
    const jaime = b.addModule("jaime", .{
        .root_source_file = b.path("src/Jaime.zig"),
        .target = target,
        .optimize = optimize,
    });

    _ = jaime;
}
