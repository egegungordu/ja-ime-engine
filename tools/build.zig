const std = @import("std");

pub const Options = struct {
    src_dir: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    imports: []const std.Build.Module.Import = &.{},
};

pub fn build(b: *std.Build, opts: Options) std.Build.LazyPath {
    const dict_builder_exe = b.addExecutable(.{
        .name = "dictionary_builder",
        .root_source_file = b.path(b.fmt("{s}/dictionary_builder.zig", .{opts.src_dir})),
        .target = b.host,
        .optimize = .Debug,
    });
    for (opts.imports) |import| {
        dict_builder_exe.root_module.addImport(import.name, import.module);
    }
    const combined_dictionary = b.path("src/dictionary/combined_dictionary.tsv");
    const cost_matrix = b.path("src/dictionary/cost_matrix.tsv");
    dict_builder_exe.root_module.addAnonymousImport("combined_dictionary.tsv", .{
        .root_source_file = combined_dictionary,
    });
    dict_builder_exe.root_module.addAnonymousImport("cost_matrix.tsv", .{
        .root_source_file = cost_matrix,
    });
    const run_dict_builder_exe = b.addRunArtifact(dict_builder_exe);
    return run_dict_builder_exe.addOutputFileArg("ipadic.bin");
}

// const ToolOptions = struct {
//     name: []const u8,
//     run_desc: []const u8,
//     src: []const u8,
//     target: std.Build.ResolvedTarget,
//     optimize: std.builtin.OptimizeMode,
// };

// fn buildTool(b: *std.Build, options: ToolOptions) void {
//     const exe = b.addExecutable(.{
//         .name = options.name,
//         .root_source_file = b.path(options.src),
//         .target = options.target,
//         .optimize = options.optimize,
//     });
//     b.installArtifact(exe);

//     const run = b.addRunArtifact(exe);
//     run.step.dependOn(b.getInstallStep());
//     b.step(b.fmt("run-{s}", .{options.name}), options.run_desc).dependOn(&run.step);
// }
