const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const core = @import("core");
const datastructs = @import("datastructs");
const DictionarySerializer = core.dictionary.DictionarySerializer;
const Dictionary = core.dictionary.Dictionary;
const WordEntry = core.WordEntry;
const LoudsTrieBuilder = datastructs.louds_trie.LoudsTrieBuilder;

test "dictionary serializer: serialize & deserialize" {
    const allocator = testing.allocator;
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    var dict = try createTestDictionary(allocator);
    defer dict.deinit();

    // serialize
    try DictionarySerializer.serialize(&dict, buffer.writer());

    // deserialize
    var stream = std.io.fixedBufferStream(buffer.items);
    var dict_deserialized = try DictionarySerializer.deserialize(allocator, stream.reader());
    defer dict_deserialized.deinit();

    try testing.expectEqualDeep(dict, dict_deserialized);
}

fn createTestDictionary(allocator: mem.Allocator) !Dictionary {
    var bldr = LoudsTrieBuilder(WordEntry).init(allocator);
    defer bldr.deinit();

    const entries = [_]struct { []const u8, WordEntry }{
        .{ "ひらめく", .{ .word = "閃く" } },
        .{ "ひらく", .{ .word = "開く" } },
        .{ "ひらける", .{ .word = "開ける" } },
        .{ "たべる", .{ .word = "食べる" } },
        .{ "たべつづける", .{ .word = "食べ続ける" } },
        .{ "たべすぎる", .{ .word = "食べ過ぎる" } },
        .{ "こうがく", .{ .word = "工学" } },
        .{ "こうがく", .{ .word = "光学" } },
        .{ "こうがく", .{ .word = "高額" } },
    };

    for (entries) |entry| {
        try bldr.insert(entry[0], entry[1]);
    }

    var ltrie = try bldr.build();
    errdefer ltrie.deinit();

    const costs = std.ArrayList(i16).init(allocator);

    return .{
        .trie = ltrie,
        .costs = costs,
        .right_count = 0,
    };
}
