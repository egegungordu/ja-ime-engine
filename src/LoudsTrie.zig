const std = @import("std");
const mem = std.mem;

const SuccinctBitArray = @import("SuccinctBitArray.zig").SuccinctBitArray;
const SuccinctBitArrayBuilder = @import("SuccinctBitArray.zig").SuccinctBitArrayBuilder;
const Trie = @import("Trie.zig").Trie;
const Louds = @import("Louds.zig").Louds;
const BitArray = @import("BitArray.zig");

// TODO: take a look at decompressor/compressor https://codeberg.org/atman/zg/src/branch/master/src/CaseData.zig
// TODO: the deserializer will allocate new strings, we can also use the slices from the reader
// assuming their lifetime is longer, which will be true for @embedFile
pub fn LoudsTrieSerializer(comptime V: type) type {
    return struct {
        const Self = @This();
        const LTrie = LoudsTrie(V);

        pub fn serialize(ltrie: *const LTrie, writer: anytype) !void {
            // ltrie.labels
            try serializeStringArrayList(&ltrie.labels, writer);
            // ltrie.values
            try serializeStringArrayList(&ltrie.values, writer);
            // ltrie.value_offsets
            try serializeIntArrayList(usize, &ltrie.value_offsets, writer);
            // ltrie.louds.sba
            try serializeSuccinctBitArray(&ltrie.louds.sba, writer);
        }

        pub fn deserialize(allocator: mem.Allocator, reader: anytype) !LTrie {
            const labels = try deserializeStringArrayList(allocator, reader);
            const values = try deserializeStringArrayList(allocator, reader);
            const value_offsets = try deserializeIntArrayList(usize, allocator, reader);
            const louds_sba = try deserializeSuccinctBitArray(allocator, reader);
            return .{
                .labels = labels,
                .values = values,
                .value_offsets = value_offsets,
                .louds = Louds(32).init(louds_sba),
            };
        }

        fn serializeStringArrayList(list: *const std.ArrayList([]const u8), writer: anytype) !void {
            // First write the number of elements in the array
            try writer.writeInt(usize, list.items.len, .little);

            // For each element (which is []const u8)
            for (list.items) |str| {
                // Write number of bytes in this array
                try writer.writeInt(usize, str.len, .little);

                try writer.writeAll(str);
            }
        }

        fn serializeSuccinctBitArray(sba: *const SuccinctBitArray(32), writer: anytype) !void {
            // serialize sba.bit_array
            try serializeBitArray(&sba.bit_array, writer);
            // serialize sba.index
            try serializeIntArrayList(usize, &sba.index, writer);
        }

        fn serializeBitArray(array: *const BitArray, writer: anytype) !void {
            // bit_len: usize,
            try serializeInt(usize, array.bit_len, writer);
            // bytes: std.ArrayList(u8),
            try serializeIntArrayList(u8, &array.bytes, writer);
        }

        fn serializeInt(comptime T: type, int: T, writer: anytype) !void {
            try writer.writeInt(T, int, .little);
        }

        fn serializeIntArrayList(comptime T: type, list: *const std.ArrayList(T), writer: anytype) !void {
            // First write the number of elements in the array
            try writer.writeInt(usize, list.items.len, .little);

            // For each element (which is usize)
            for (list.items) |element| {
                // Write it
                try writer.writeInt(T, element, .little);
            }
        }

        fn deserializeStringArrayList(allocator: mem.Allocator, reader: anytype) !std.ArrayList([]const u8) {
            var list = std.ArrayList([]const u8).init(allocator);
            errdefer list.deinit();

            // Read number of elements
            const num_elements = try reader.readInt(usize, .little);

            // Allocate space for all elements
            try list.ensureTotalCapacity(num_elements);

            // For each element
            var i: usize = 0;
            while (i < num_elements) : (i += 1) {
                // Read string length
                const str_len = try reader.readInt(usize, .little);

                // Read string
                const str = reader.context.buffer[reader.context.pos .. reader.context.pos + str_len];
                try reader.skipBytes(str_len, .{});

                try list.append(str);
            }

            return list;
        }

        fn deserializeSuccinctBitArray(allocator: mem.Allocator, reader: anytype) !SuccinctBitArray(32) {
            return .{
                .bit_array = try deserializeBitArray(allocator, reader),
                .index = try deserializeIntArrayList(usize, allocator, reader),
            };
        }

        fn deserializeBitArray(allocator: mem.Allocator, reader: anytype) !BitArray {
            return .{
                .bit_len = try deserializeInt(usize, reader),
                .bytes = try deserializeIntArrayList(u8, allocator, reader),
            };
        }

        fn deserializeInt(comptime T: type, reader: anytype) !T {
            return try reader.readInt(T, .little);
        }

        fn deserializeIntArrayList(comptime T: type, allocator: mem.Allocator, reader: anytype) !std.ArrayList(T) {
            var list = std.ArrayList(T).init(allocator);
            errdefer list.deinit();

            // First read the number of elements in the array
            const num_elements = try reader.readInt(usize, .little);

            // Allocate space for all elements
            try list.ensureTotalCapacity(num_elements);

            // For each element
            var i: usize = 0;
            while (i < num_elements) : (i += 1) {
                // Read the element
                const element = try reader.readInt(T, .little);

                try list.append(element);
            }

            return list;
        }
    };
}

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

const testing = std.testing;

test "louds trie serializer: serialize & deserialize" {
    const allocator = testing.allocator;
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const Serializer = LoudsTrieSerializer([]const u8);

    var ltrie = try createTestLoudsTrie(allocator);
    defer ltrie.deinit();

    // serialize
    try Serializer.serialize(&ltrie, buffer.writer());

    // deserialize
    var stream = std.io.fixedBufferStream(buffer.items);
    var ltrie_deserialized = try Serializer.deserialize(allocator, stream.reader());
    defer ltrie_deserialized.deinit();

    for (0..ltrie.labels.items.len) |i| {
        try testing.expectEqualStrings(ltrie.labels.items[i], ltrie_deserialized.labels.items[i]);
    }
    for (0..ltrie.values.items.len) |i| {
        try testing.expectEqualStrings(ltrie.values.items[i], ltrie_deserialized.values.items[i]);
    }
    try testing.expectEqualSlices(
        usize,
        ltrie.value_offsets.items,
        ltrie_deserialized.value_offsets.items,
    );
    try testing.expectEqualStrings(
        ltrie.louds.sba.bit_array.bytes.items,
        ltrie_deserialized.louds.sba.bit_array.bytes.items,
    );
    try testing.expectEqualSlices(
        usize,
        ltrie.louds.sba.index.items,
        ltrie_deserialized.louds.sba.index.items,
    );
}

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
