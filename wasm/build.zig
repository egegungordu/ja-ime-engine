const std = @import("std");

pub const Options = struct {
    src_dir: []const u8,
    imports: []const std.Build.Module.Import = &.{},
};

pub fn build(b: *std.Build, opts: Options) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const exe = b.addExecutable(.{
        .name = "libjaime",
        .root_source_file = b.path(b.fmt("{src}/lib.zig", .{opts.src_dir})),
        .target = target,
        .optimize = .ReleaseSmall,
    });
    for (opts.imports) |import| {
        exe.root_module.addImport(import.name, import.module);
    }

    exe.global_base = 6560;
    exe.entry = .disabled;
    exe.rdynamic = true;

    const number_of_pages = 1024;
    exe.stack_size = std.wasm.page_size;
    exe.initial_memory = std.wasm.page_size * number_of_pages;
    exe.max_memory = std.wasm.page_size * number_of_pages;

    b.installArtifact(exe);
}
