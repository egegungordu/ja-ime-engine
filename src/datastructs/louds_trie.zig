const std = @import("std");
const mem = std.mem;

const SuccinctBitArray = @import("succinct_bit_array.zig").SuccinctBitArray;
const SuccinctBitArrayBuilder = @import("succinct_bit_array.zig").SuccinctBitArrayBuilder;
const Trie = @import("trie.zig").Trie;
const Louds = @import("louds.zig").Louds;
const BitArray = @import("BitArray.zig");

pub fn LoudsTrieBuilder(comptime V: type) type {
    return struct {
        const Self = @This();

        allocator: mem.Allocator,
        trie: Trie(V),

        pub fn init(allocator: mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .trie = Trie(V).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.trie.deinit();
        }

        pub fn insert(self: *Self, key: []const u8, value: V) !void {
            try self.trie.insert(key, value);
        }

        pub fn build(self: *Self) !LoudsTrie(V) {
            var trie_it = try self.trie.iterator(self.allocator);
            defer trie_it.deinit();

            var sbab = SuccinctBitArrayBuilder(32).init(self.allocator);
            defer sbab.deinit();

            var labels = std.ArrayList([]const u8).init(self.allocator);
            errdefer labels.deinit();
            var values = std.ArrayList(V).init(self.allocator);
            errdefer values.deinit();
            var value_offsets = std.ArrayList(usize).init(self.allocator);
            errdefer value_offsets.deinit();
            var current_offset: usize = 0;

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

                try values.appendSlice(node.values.items);

                try value_offsets.append(current_offset);
                current_offset += node.values.items.len;
            }

            const sb = try sbab.build();
            const louds = Louds(32).init(sb);

            return LoudsTrie(V){
                .labels = labels,
                .values = values,
                .value_offsets = value_offsets,
                .louds = louds,
            };
        }
    };
}

pub fn LoudsTrie(comptime V: type) type {
    return struct {
        const Self = @This();

        pub const MatchResult = struct { depth: usize, values: []const V };

        labels: std.ArrayList([]const u8),
        values: std.ArrayList(V),
        value_offsets: std.ArrayList(usize),
        louds: Louds(32),

        pub fn deinit(self: *Self) void {
            self.labels.deinit();
            self.values.deinit();
            self.value_offsets.deinit();
            self.louds.deinit();
        }

        /// Returns the values associated with an exact match of the given key, or null if not found.
        /// The returned MatchResult contains the depth of the match and the values at that node.
        pub fn exactMatch(self: Self, key: []const u8) !?MatchResult {
            var key_it = (try std.unicode.Utf8View.init(key)).iterator();
            var current_node = self.louds.getRoot();
            var depth: usize = 0;
            while (key_it.nextCodepointSlice()) |char| {
                while (!mem.eql(u8, self.labels.items[current_node.edge_index.?], char)) {
                    if (try self.louds.hasNextSibling(current_node)) {
                        self.louds.nextSibling(&current_node);
                    } else {
                        return null;
                    }
                }
                try self.louds.firstChild(&current_node);
                depth += 1;
                if (self.louds.isLeaf(current_node)) {
                    if (try self.getValues(current_node)) |values| {
                        return .{ .depth = depth, .values = values };
                    }
                    return null;
                }
            }
            if (try self.getValues(current_node)) |values| {
                return .{ .depth = depth, .values = values };
            }
            return null;
        }

        /// Returns all values found at each prefix of the given key.
        /// For example, for key "hello", it will return values found at "h", "he", "hel", "hell", and "hello".
        pub fn prefixMatch(self: Self, allocator: mem.Allocator, key: []const u8) !std.ArrayList(MatchResult) {
            var results = std.ArrayList(MatchResult).init(allocator);
            errdefer results.deinit();

            var key_it = (try std.unicode.Utf8View.init(key)).iterator();
            var current_node = self.louds.getRoot();
            var depth: usize = 0;

            while (key_it.nextCodepointSlice()) |char| {
                while (!mem.eql(u8, self.labels.items[current_node.edge_index.?], char)) {
                    if (try self.louds.hasNextSibling(current_node)) {
                        self.louds.nextSibling(&current_node);
                    } else {
                        return results;
                    }
                }
                try self.louds.firstChild(&current_node);
                depth += 1;

                if (try self.getValues(current_node)) |values| {
                    try results.append(.{
                        .depth = depth,
                        .values = values,
                    });
                }

                if (self.louds.isLeaf(current_node)) {
                    return results;
                }
            }

            return results;
        }

        /// Calculate the size of the trie in memory, in bytes
        fn calcSize(self: Self) usize {
            const label_size = blk: {
                var size = self.labels.items.len * @sizeOf([]const u8);
                for (self.labels.items) |item| {
                    size += @sizeOf(usize) + @sizeOf([*]const u8) + item.len * @sizeOf(u8);
                }
                break :blk size;
            };
            const values_size = blk: {
                var size = self.values.items.len * @sizeOf([]const u8);
                for (self.values.items) |item| {
                    size += @sizeOf(usize) + @sizeOf([*]const u8) + item.len * @sizeOf(u8);
                }
                break :blk size;
            };

            return label_size +
                values_size +
                self.louds.sba.bit_array.bytes.items.len * @sizeOf(u8) +
                self.louds.sba.index.items.len * @sizeOf(usize) +
                self.value_offsets.items.len * @sizeOf(usize);
        }

        fn getValues(self: Self, node: Louds(32).Node) !?[]const V {
            const node_index = try self.louds.getNodeIndex(node);
            if (node_index + 1 >= self.values.items.len) {}
            const start = self.value_offsets.items[node_index];
            const end = blk: {
                if (node_index + 1 < self.value_offsets.items.len) {
                    break :blk self.value_offsets.items[node_index + 1];
                }
                break :blk self.values.items.len;
            };
            if (start == end) return null;
            return self.values.items[start..end];
        }
    };
}
