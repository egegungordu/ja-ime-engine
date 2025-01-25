const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const datastructs = @import("datastructs");
const LoudsTrie = datastructs.louds_trie.LoudsTrie;
const LoudsTrieBuilder = datastructs.louds_trie.LoudsTrieBuilder;

test "louds trie: exact match" {
    const allocator = testing.allocator;
    const MatchResult = LoudsTrie([]const u8).MatchResult;

    var ltrie: LoudsTrie([]const u8) = try createTestLoudsTrie(allocator);
    defer ltrie.deinit();

    try testing.expectEqualDeep(
        MatchResult{
            .depth = 2,
            .values = &.{"喜怒"},
        },
        (try ltrie.exactMatch("きど")).?,
    );
    try testing.expectEqualDeep(
        MatchResult{
            .depth = 4,
            .values = &.{"哀楽"},
        },
        (try ltrie.exactMatch("あいらく")).?,
    );
    try testing.expectEqualDeep(
        MatchResult{
            .depth = 2,
            .values = &.{ "乗る", "載る" },
        },
        (try ltrie.exactMatch("のる")).?,
    );

    // Test empty string
    try testing.expectEqual(@as(?MatchResult, null), try ltrie.exactMatch(""));

    // Test non-existent string
    try testing.expectEqual(@as(?MatchResult, null), try ltrie.exactMatch("xyz"));
}

test "louds trie: prefix match" {
    const allocator = testing.allocator;
    const MatchResult = LoudsTrie([]const u8).MatchResult;

    var ltrie = try createTestLoudsTrie(allocator);
    defer ltrie.deinit();

    var results = try ltrie.prefixMatch(allocator, "こんにちは");
    defer results.deinit();

    try testing.expectEqual(@as(usize, 4), results.items.len);

    try testing.expectEqualDeep(
        &[_]MatchResult{
            .{
                .depth = 1,
                .values = &.{ "子", "個" },
            },
            .{
                .depth = 2,
                .values = &.{"根"},
            },
            .{
                .depth = 4,
                .values = &.{"今日"},
            },
            .{
                .depth = 5,
                .values = &.{"こんにちは"},
            },
        },
        results.items,
    );

    // Test empty string
    var empty_results = try ltrie.prefixMatch(allocator, "");
    defer empty_results.deinit();
    try testing.expectEqual(@as(usize, 0), empty_results.items.len);

    // Test non-existent string
    var nonexistent_results = try ltrie.prefixMatch(allocator, "xyz");
    defer nonexistent_results.deinit();
    try testing.expectEqual(@as(usize, 0), nonexistent_results.items.len);
}

fn createTestLoudsTrie(allocator: mem.Allocator) !LoudsTrie([]const u8) {
    var bldr = LoudsTrieBuilder([]const u8).init(allocator);
    defer bldr.deinit();
    try bldr.insert("きど", "喜怒");
    try bldr.insert("あいらく", "哀楽");
    try bldr.insert("のる", "乗る");
    try bldr.insert("のる", "載る");
    try bldr.insert("こ", "子");
    try bldr.insert("こ", "個");
    try bldr.insert("こん", "根");
    try bldr.insert("こんにち", "今日");
    try bldr.insert("こんにちは", "こんにちは");
    return try bldr.build();
}
