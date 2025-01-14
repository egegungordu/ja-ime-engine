const std = @import("std");
const mem = std.mem;

const SuccinctBitArray = @import("SuccinctBitArray.zig").SuccinctBitArray;
const SuccinctBitArrayBuilder = @import("SuccinctBitArray.zig").SuccinctBitArrayBuilder;
const Trie = @import("Trie.zig").Trie;
const Louds = @import("Louds.zig").Louds;
const Dictionary = @import("Dictionary.zig").Dictionary;

pub fn LoudsTrieBuilder(comptime V: type) type {
    return struct {
        allocator: mem.Allocator,
        trie: Trie(V),

        pub fn init(allocator: mem.Allocator) LoudsTrieBuilder(V) {
            return .{
                .allocator = allocator,
                .trie = Trie(V).init(allocator),
            };
        }

        pub fn deinit(self: *LoudsTrieBuilder(V)) void {
            self.trie.deinit();
        }

        pub fn insert(self: *LoudsTrieBuilder(V), key: []const u8, value: V) !void {
            try self.trie.insert(key, value);
        }

        pub fn build(self: *LoudsTrieBuilder(V)) !LoudsTrie {
            var trie_it = try self.trie.iterator(self.allocator);
            defer trie_it.deinit();

            var sbab = SuccinctBitArrayBuilder(32).init(self.allocator);
            defer sbab.deinit();

            var labels = std.ArrayList([]const u8).init(self.allocator);

            // Push super root
            try sbab.append(1);
            try sbab.append(0);
            // Put the nodes into the bit array
            // 1 for each edge, 0 for the node
            // Also collect the labels
            while (try trie_it.next()) |node| {
                var it = node.edges.keyIterator();
                while (it.next()) |val| {
                    try sbab.append(1);
                    try labels.append(val.*);
                }
                try sbab.append(0);
            }

            const sb = try sbab.build();
            const louds = Louds(32).init(sb);

            return LoudsTrie{
                .labels = labels,
                .louds = louds,
            };
        }
    };
}

pub const LoudsTrie = struct {
    labels: std.ArrayList([]const u8),
    louds: Louds(32),

    pub fn deinit(self: *LoudsTrie) void {
        self.labels.deinit();
        self.louds.deinit();
    }

    pub fn exactMatch(self: LoudsTrie, key: []const u8) !bool {
        var key_it = (try std.unicode.Utf8View.init(key)).iterator();
        var current_node = self.louds.getRoot();
        while (key_it.nextCodepointSlice()) |char| {
            std.debug.print("char: {s}, node_id: {d}, node_index: {d}\n", .{ char, current_node.id, current_node.index });
            while (!mem.eql(u8, self.labels.items[current_node.id], char)) {
                std.debug.print("\tnot equal\n", .{});
                std.debug.print("\t[id]: {s}\n", .{self.labels.items[current_node.id]});
                std.debug.print("\tnode_id: {d}, node_index: {d}\n", .{ current_node.id, current_node.index });
                std.debug.print("\tnext_sibling: {}\n", .{try self.louds.hasNextSibling(current_node)});
                if (try self.louds.hasNextSibling(current_node)) {
                    self.louds.nextSibling(&current_node);
                } else {
                    return false;
                }
            }
            try self.louds.firstChild(&current_node);
        }
        // TODO: check if it has values, we need to use trie values, which we currently ignore at the builder!!!!
        return true;
    }

    // TODO: Implement everything else
};

test "test exists" {
    const allocator = std.testing.allocator;

    var dict = try Dictionary.init(allocator);
    var dict_it = dict.iterator();
    defer dict.deinit();

    var ltrie_builder = LoudsTrieBuilder([]const u8).init(allocator);
    defer ltrie_builder.deinit();

    var i: usize = 0;
    while (dict_it.next()) |pair| {
        try ltrie_builder.insert(pair[0], pair[1]);
        if (i == 10) break;
        i += 1;
    }

    var ltrie = try ltrie_builder.build();
    defer ltrie.deinit();

    for (ltrie.labels.items) |label| {
        std.debug.print("label: {s}\n", .{label});
    }

    std.debug.print("louds: {}\n", .{ltrie.louds.sba});

    const res = try ltrie.exactMatch("やぼったい");
    std.debug.print("\nres: {}\n", .{res});
}
