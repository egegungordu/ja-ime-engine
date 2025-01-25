const std = @import("std");

pub const Options = struct {
    src_dir: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    imports: []const std.Build.Module.Import = &.{},
};

pub fn build(b: *std.Build, opts: Options) void {
    const test_step = b.step("test", "Run unit tests");
    const unit_test = b.addTest(.{
        .root_source_file = b.path(b.fmt("{s}/tests.zig", .{opts.src_dir})),
        .target = opts.target,
    });
    for (opts.imports) |import| {
        unit_test.root_module.addImport(import.name, import.module);
    }
    const run_unit_test = b.addRunArtifact(unit_test);

    // disable caching on tests so they run every time
    run_unit_test.has_side_effects = true;

    test_step.dependOn(&run_unit_test.step);
}
