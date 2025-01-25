const std = @import("std");

const WordEntry = @import("WordEntry.zig");
const datastructs = @import("datastructs");
const LoudsTrie = datastructs.louds_trie.LoudsTrie;
const LoudsTrieBuilder = datastructs.louds_trie.LoudsTrieBuilder;

/// A lattice structure representing all possible segmentations of an input string
pub const Lattice = struct {
    const Self = @This();

    /// List of nodes at each position in the input string
    nodes: std.ArrayList(std.ArrayList(Node)),
    allocator: std.mem.Allocator,

    pub const Node = struct {
        /// The position where this node starts in the input string
        start_pos: usize,
        /// The length of this node in characters
        length: usize,
        /// The word/morpheme value associated with this node
        value: WordEntry,
        /// The lowest total cost up to this node
        cost: isize,
    };

    // TODO: since we know how many nodes each position will have, we can also initCapacity the inner arrays
    // with a new argument
    pub fn init(allocator: std.mem.Allocator, max_len: usize) !Self {
        var nodes = try std.ArrayList(std.ArrayList(Node)).initCapacity(allocator, max_len);
        var i: usize = 0;
        while (i < max_len) : (i += 1) {
            try nodes.append(std.ArrayList(Node).init(allocator));
        }
        return Self{
            .nodes = nodes,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.nodes.items) |*node_list| {
            node_list.deinit();
        }
        self.nodes.deinit();
    }

    /// Add a node to the lattice at the given position
    pub fn addNode(self: *Self, node: Node) !void {
        try self.nodes.items[node.start_pos].append(node);
    }
};

/// Create a lattice from the input string using the dictionary trie
/// The lattice will contain all possible segmentations of the input string
/// based on the words found in the dictionary
pub fn createLattice(allocator: std.mem.Allocator, input: []const u8, dict: *const LoudsTrie(WordEntry)) !Lattice {
    var utf8_view = try std.unicode.Utf8View.init(input);
    var char_count: usize = 0;
    {
        var it = utf8_view.iterator();
        while (it.nextCodepointSlice() != null) char_count += 1;
    }

    var lattice = try Lattice.init(allocator, char_count);
    errdefer lattice.deinit();

    // For each starting position in the input string
    var start_pos: usize = 0;
    var start_it = utf8_view.iterator();
    while (start_pos < char_count) : (start_pos += 1) {
        // Get the substring from this position to the end
        const remaining = start_it.bytes[start_it.i..];
        // Find all possible prefixes that match in the dictionary
        var matches = try dict.prefixMatch(allocator, remaining);
        defer matches.deinit();

        // Add each match as a node in the lattice
        for (matches.items) |match_result| {
            for (match_result.values) |value| {
                try lattice.addNode(.{
                    .start_pos = start_pos,
                    .length = match_result.depth,
                    .value = value,
                    .cost = 0,
                });
            }
        }

        _ = start_it.nextCodepointSlice();
    }

    return lattice;
}

const testing = std.testing;

test "lattice: create lattice" {
    const allocator = testing.allocator;

    // Create a test dictionary
    var dict = try createTestDict(allocator);
    defer dict.deinit();

    // Create a lattice for the input "こんにちは"
    var lattice = try createLattice(allocator, "こんにちは", &dict);
    defer lattice.deinit();

    // Test the structure of the lattice
    try testing.expectEqual(@as(usize, 5), lattice.nodes.items.len);

    // // Test nodes at position 0 (こ, こん, こんにち, こんにちは)
    // {
    //     const pos0_nodes = lattice.nodes.items[0];
    //     try testing.expectEqual(@as(usize, 6), pos0_nodes.items.len); // こ(2), こん(1), こんにち(1), こんにちは(1)

    //     // Count nodes for each value at position 0
    //     var ko_count: usize = 0;
    //     var kon_count: usize = 0;
    //     var konnichiwa_count: usize = 0;

    //     for (pos0_nodes.items) |node| {
    //         if (node.length == 1) ko_count += 1;
    //         if (node.length == 2) kon_count += 1;
    //         if (node.length == 5) konnichiwa_count += 1;
    //     }

    //     try testing.expectEqual(@as(usize, 2), ko_count); // "子", "個"
    //     try testing.expectEqual(@as(usize, 1), kon_count); // "根"
    //     try testing.expectEqual(@as(usize, 1), konnichiwa_count); // "こんにちは"
    // }
}

fn createTestDict(allocator: std.mem.Allocator) !LoudsTrie(WordEntry) {
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

    return try bldr.build();
}
