const std = @import("std");

const LoudsTrieSerializer = @import("LoudsTrie").LoudsTrieSerializer([]const u8);
const LoudsTrieBuilder = @import("LoudsTrie").LoudsTrieBuilder([]const u8);

const in_file = @embedFile("combined_dictionary.tsv");

// TODO: use system endian for serialization endianness
// TODO: make this faster
//       the hotspot is insert method in Trie.
// currently takes 55 seconds
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var bldr = LoudsTrieBuilder.init(allocator);
    defer bldr.deinit();

    var line_it = std.mem.splitScalar(u8, in_file, '\n');
    while (line_it.next()) |line| {
        var word_it = std.mem.splitScalar(u8, line, '\t');
        const reading = word_it.next().?;
        _ = word_it.next();
        _ = word_it.next();
        _ = word_it.next();
        if (word_it.next()) |word| {
            try bldr.insert(reading, word);
        }
    }

    var ltrie = try bldr.build();
    defer ltrie.deinit();

    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();
    _ = args_iter.skip();
    const output_path = args_iter.next() orelse @panic("No output file arg!");

    var out_file = try std.fs.cwd().createFile(output_path, .{});
    defer out_file.close();

    try LoudsTrieSerializer.serialize(&ltrie, out_file.writer());
}
