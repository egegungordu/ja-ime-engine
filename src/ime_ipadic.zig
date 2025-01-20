const std = @import("std");
const mem = std.mem;
const ime_core = @import("ime_core.zig");
const louds_trie = @import("LoudsTrie.zig");
const LoudsTrie = louds_trie.LoudsTrie([]const u8);
const LoudsTrieSerializer = louds_trie.LoudsTrieSerializer([]const u8);
const LoudsTrieBuilder = louds_trie.LoudsTrieBuilder([]const u8);

const ipadic_bytes = @embedFile("ipadic");

pub const IpadicLoader = struct {
    pub fn loadTrie(allocator: mem.Allocator) !LoudsTrie {
        var dict_fbs = std.io.fixedBufferStream(ipadic_bytes);

        return try LoudsTrieSerializer.deserialize(
            allocator,
            dict_fbs.reader(),
        );
    }

    pub fn freeTrie(ltrie: *LoudsTrie) void {
        ltrie.deinit();
    }
};

pub const ImeIpadic = ime_core.Ime(IpadicLoader);
