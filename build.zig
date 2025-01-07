const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Modules
    // jaime
    const jaime = b.addModule("jaime", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    _ = jaime;

    // Add option to build wasm
    const build_wasm = b.option(bool, "lib-wasm", "Build the WebAssembly library") orelse false;
    if (build_wasm) {
        buildWasmLib(b);
    }
}

fn buildWasmLib(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const exe = b.addExecutable(.{
        .name = "libjaime",
        .root_source_file = b.path("src/lib_wasm.zig"),
        .target = target,
        .optimize = .ReleaseSmall,
    });

    exe.global_base = 6560;
    exe.entry = .disabled;
    exe.rdynamic = true;

    const number_of_pages = 2;
    exe.stack_size = std.wasm.page_size;
    exe.initial_memory = std.wasm.page_size * number_of_pages;
    exe.max_memory = std.wasm.page_size * number_of_pages;

    b.installArtifact(exe);
}
