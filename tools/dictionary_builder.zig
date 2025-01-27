const std = @import("std");

const core = @import("core");
const datastructs = @import("datastructs");
const WordEntry = core.WordEntry;
const LoudsTrieBuilder = datastructs.louds_trie.LoudsTrieBuilder(WordEntry);
const DictionarySerializer = core.dictionary.DictionarySerializer;

const comb_dict = @embedFile("combined_dictionary.tsv");
const cost_mat = @embedFile("cost_matrix.tsv");

// TODO: use system endian for serialization endianness? (maybe not needed since we do .little read & write)
// TODO: make this faster
//       the hotspot is insert method in Trie.
// currently takes 55 seconds
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var cost_it = std.mem.tokenizeAny(u8, cost_mat, "\n\r\t");
    const left_count = try std.fmt.parseInt(u32, cost_it.next().?, 10);
    const right_count = try std.fmt.parseInt(u32, cost_it.next().?, 10);
    var cost_arr = try std.ArrayList(i16).initCapacity(allocator, left_count * right_count);
    defer cost_arr.deinit();

    for (0..left_count * right_count) |_| {
        _ = cost_it.next();
        _ = cost_it.next();
        cost_arr.appendAssumeCapacity(try std.fmt.parseInt(i16, cost_it.next().?, 10));
    }

    var bldr = LoudsTrieBuilder.init(allocator);
    defer bldr.deinit();

    var dict_it = std.mem.tokenizeAny(u8, comb_dict, "\n\r\t");
    while (true) {
        const reading = dict_it.next() orelse break;
        const left_id = try std.fmt.parseInt(u32, dict_it.next().?, 10);
        const right_id = try std.fmt.parseInt(u32, dict_it.next().?, 10);
        const cost = try std.fmt.parseInt(i16, dict_it.next().?, 10);
        const word = dict_it.next().?;
        try bldr.insert(reading, .{
            .word = word,
            .left_id = left_id,
            .right_id = right_id,
            .cost = cost,
        });
    }

    var ltrie = try bldr.build();
    defer ltrie.deinit();

    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();
    _ = args_iter.skip();
    const output_path = args_iter.next() orelse @panic("No output file arg!");

    var out_file = try std.fs.cwd().createFile(output_path, .{});
    defer out_file.close();

    try DictionarySerializer.serialize(&.{
        .trie = ltrie,
        .costs = cost_arr,
        .right_count = right_count,
    }, out_file.writer());
}
