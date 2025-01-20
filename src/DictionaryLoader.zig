const std = @import("std");
const mem = std.mem;
const louds_trie = @import("LoudsTrie.zig");
const LoudsTrie = louds_trie.LoudsTrie([]const u8);
const LoudsTrieSerializer = louds_trie.LoudsTrieSerializer([]const u8);
const LoudsTrieBuilder = louds_trie.LoudsTrieBuilder([]const u8);

pub const TestingDictionaryLoader = struct {
    pub fn loadTrie(allocator: mem.Allocator) !LoudsTrie {
        var bldr = LoudsTrieBuilder.init(allocator);
        defer bldr.deinit();

        // Common words for testing (hiragana -> kanji/word mappings)
        const entries = [_]struct { []const u8, []const u8 }{
            .{ "こんにちは", "今日は" },
            .{ "ありがとう", "有難う" },
            .{ "わたし", "私" },
            .{ "にほん", "日本" },
            .{ "おはよう", "お早う" },
            .{ "さようなら", "左様なら" },
            .{ "がっこう", "学校" },
            .{ "でんしゃ", "電車" },
        };

        for (entries) |entry| {
            try bldr.insert(entry[0], entry[1]);
        }

        return bldr.build();
    }

    pub fn freeTrie(allocator: mem.Allocator, ltrie: *LoudsTrie) void {
        _ = allocator;
        ltrie.deinit();
    }
};
