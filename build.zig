const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Private module used in dictionary builder
    const louds_trie = b.createModule(.{
        .root_source_file = b.path("src/LoudsTrie.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Dictionary builder
    // Build the trie from the tsv and serialize it to a file
    const dict_builder_exe = b.addExecutable(.{
        .name = "dictionary_builder",
        .root_source_file = b.path("tools/dictionary_builder.zig"),
        .target = b.host,
        .optimize = .Debug,
    });
    dict_builder_exe.root_module.addImport("LoudsTrie", louds_trie);
    const combined_dictionary = b.path("src/dictionary/combined_dictionary.tsv");
    dict_builder_exe.root_module.addAnonymousImport("combined_dictionary.tsv", .{
        .root_source_file = combined_dictionary,
    });
    const run_dict_builder_exe = b.addRunArtifact(dict_builder_exe);
    const run_dict_builder_out = run_dict_builder_exe.addOutputFileArg("ipadic.bin");

    // Public (exported) modules
    // TODO: currently, can't import multiple modules at the same time because they all import
    // src/ime_core.zig, and we get the error: file exists in multiple modules
    // may be able to fix by adding the ime_core to the kana and ime-ipadic modules by addImport?

    // kana
    _ = b.addModule("kana", .{
        .root_source_file = b.path("src/kana.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ime-core
    _ = b.addModule("ime_core", .{
        .root_source_file = b.path("src/ime_core.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ime-ipadic
    const ime_ipadic = b.addModule("ime_ipadic", .{
        .root_source_file = b.path("src/ime_ipadic.zig"),
        .target = target,
        .optimize = optimize,
    });
    ime_ipadic.addAnonymousImport("ipadic", .{ .root_source_file = run_dict_builder_out });

    const wasm_exe = buildWasmLib(b);
    _ = wasm_exe;
    // wasm_exe.root_module.addImport("ime_core", ime_core);

    _ = buildTests(b, target, optimize);
    const test_ime_ipadic = buildImeIpadicTests(b, target, optimize);
    test_ime_ipadic.root_module.addAnonymousImport("ipadic", .{ .root_source_file = run_dict_builder_out });
}

fn buildImeIpadicTests(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.Mode) *std.Build.Step.Compile {
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/ime_ipadic.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // disable caching on tests so they run every time
    run_unit_tests.has_side_effects = true;

    const test_step = b.step("test-ime-ipadic", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    return unit_tests;
}

fn buildWasmLib(b: *std.Build) *std.Build.Step.Compile {
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

    return exe;
}

fn buildTests(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.Mode) *std.Build.Step.Compile {
    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/kana.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // disable caching on tests so they run every time
    run_unit_tests.has_side_effects = true;

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    return unit_tests;
}
