const std = @import("std");
const mem = std.mem;

const WordEntry = @import("WordEntry.zig");
const Dictionary = @import("dictionary.zig").Dictionary;
const datastructs = @import("datastructs");
const LoudsTrie = datastructs.louds_trie.LoudsTrie;
const LoudsTrieBuilder = datastructs.louds_trie.LoudsTrieBuilder;

/// A lattice structure representing all possible segmentations of an input string
pub const Lattice = struct {
    const Self = @This();

    /// List of nodes at each position in the input string
    nodes: std.ArrayList(std.ArrayList(Node)),
    allocator: mem.Allocator,

    pub const Node = struct {
        special_node: bool,
        /// The position where this node starts in the input string
        start_pos: usize,
        /// The length of this node in characters
        length: usize,
        /// The word/morpheme value associated with this node
        value: WordEntry,
        /// Nodes that are leading up to this node
        incoming_nodes: std.ArrayList(*const Node),
        /// Lowest cost incoming node
        lowest_incoming_node: ?*const Node,
        /// Minimum cumulative cost from this node
        cost: i64,

        fn lessThan(context: void, a: Node, b: Node) bool {
            _ = context;
            return a.cost < b.cost;
        }
    };

    // pub const Path = struct {
    //     nodes: []Node,
    //     total_cost: isize,

    //     fn lessThan(context: void, a: Path, b: Path) bool {
    //         _ = context;
    //         return a.total_cost < b.total_cost;
    //     }
    // };

    // TODO: since we know how many nodes each position will have, we can also initCapacity the inner arrays
    // with a new argument
    pub fn init(allocator: mem.Allocator, max_len: usize) !Self {
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
            for (node_list.items) |node| {
                node.incoming_nodes.deinit();
            }
            node_list.deinit();
        }
        self.nodes.deinit();
    }

    /// Add a node to the lattice at the given position
    pub fn addNode(self: *Self, node: Node) !void {
        try self.nodes.items[node.start_pos].append(node);
    }

    /// Find the top `n` least cost paths in the lattice
    pub fn findBestPath(self: *Self, dict: *const Dictionary) ![]WordEntry {
        if (self.nodes.items.len == 0) {
            return error.LatticeIsEmpty;
        }

        for (self.nodes.items, 0..) |layer, level| {
            // std.debug.print("level: {d}\n", .{level});
            for (layer.items) |*node| {
                var least_incoming_cost: i64 = std.math.maxInt(i64);
                for (node.incoming_nodes.items) |incoming| {
                    const incoming_cost = @as(i64, @intCast(dict.getCost(incoming.value.right_id, node.value.left_id))) + incoming.cost;
                    if (incoming_cost < least_incoming_cost) {
                        node.lowest_incoming_node = incoming;
                        least_incoming_cost = incoming_cost;
                    }
                    // std.debug.print("\ts: {d}\tl: {d}\tw: {s}\n", .{ incoming.start_pos, incoming.length, incoming.value.word });
                }
                if (node.incoming_nodes.items.len == 0) {
                    // this is a node without any incoming nodes, ignore it
                    if (!node.special_node) {
                        continue;
                    }
                    // we are either bos or eos
                    node.cost = 0;
                } else {
                    node.cost = node.value.cost + least_incoming_cost;
                }
                // std.debug.print("node:\tcost: {d}\tword: {s}\tl: {d}\tr: {d}\tc: {d}\n", .{ node.cost, node.value.word, node.value.left_id, node.value.right_id, node.value.cost });
                // if (node.lowest_incoming_node != null) {
                //     std.debug.print("\tbest: s: {d}\tl: {d}\tw: {s}\n", .{ node.lowest_incoming_node.?.start_pos, node.lowest_incoming_node.?.length, node.lowest_incoming_node.?.value.word });
                // }

                // find the outgoing paths and this node to their incoming nodes
                const outgoing_level = level + node.length;
                if (self.nodes.items.len > outgoing_level) {
                    for (self.nodes.items[outgoing_level].items) |*outgoing_node| {
                        try outgoing_node.incoming_nodes.append(node);
                    }
                }
            }
        }

        // Second pass: backtrack from end to start to build the path
        var path = std.ArrayList(WordEntry).init(self.allocator);
        errdefer path.deinit();

        // Start from the EOS node (last position, first node)
        var iter_node: ?*const Node = &self.nodes.items[self.nodes.items.len - 1].items[0];
        while (iter_node) |node| : (iter_node = node.lowest_incoming_node) {
            // Skip BOS and EOS nodes (they have empty word slices)
            if (node.value.word.len > 0) {
                try path.append(node.value);
            }
            // std.debug.print("{s}\tnode cost: {d}\n", .{ node.value.word, node.cost });
            // const connection_cost: ?i16 = blk: {
            //     if (node.lowest_incoming_node == null) break :blk null;
            //     break :blk dict.getCost(node.lowest_incoming_node.?.value.right_id, node.value.left_id);
            // };
            // std.debug.print("word cost:\t\t{d}\n", .{node.value.cost});
            // std.debug.print("connection cost:\t{?d}\t\n", .{connection_cost});
        }

        const owned_path = try path.toOwnedSlice();
        std.mem.reverse(WordEntry, owned_path);
        return owned_path;
    }
};

/// Create a lattice from the input string using the dictionary trie
/// The lattice will contain all possible segmentations of the input string
/// based on the words found in the dictionary
pub fn createLattice(allocator: mem.Allocator, input: []const u8, dict: *const Dictionary) !Lattice {
    var utf8_view = try std.unicode.Utf8View.init(input);
    var char_count: usize = 0;
    {
        var it = utf8_view.iterator();
        while (it.nextCodepointSlice() != null) char_count += 1;
    }

    var lattice = try Lattice.init(allocator, char_count + 2);
    errdefer lattice.deinit();

    const bos_node = Lattice.Node{
        .special_node = true,
        .start_pos = 0,
        .length = 1,
        .value = .{ .word = &.{} },
        .incoming_nodes = std.ArrayList(*const Lattice.Node).init(allocator),
        .lowest_incoming_node = null,
        .cost = 0,
    };

    const eos_node = Lattice.Node{
        .special_node = true,
        .start_pos = char_count + 1,
        .length = 0,
        .value = .{ .word = &.{} },
        .incoming_nodes = std.ArrayList(*const Lattice.Node).init(allocator),
        .lowest_incoming_node = null,
        .cost = 0,
    };

    try lattice.addNode(bos_node);
    try lattice.addNode(eos_node);

    // For each starting position in the input string
    var start_pos: usize = 0;
    var start_it = utf8_view.iterator();
    while (start_pos < char_count) : (start_pos += 1) {
        // Get the substring from this position to the end
        const remaining = start_it.bytes[start_it.i..];
        // Find all possible prefixes that match in the dictionary
        var matches = try dict.trie.prefixMatch(allocator, remaining);
        defer matches.deinit();

        // Add each match as a node in the lattice
        for (matches.items) |match_result| {
            for (match_result.values) |value| {
                try lattice.addNode(.{
                    .special_node = false,
                    .start_pos = start_pos + 1,
                    .length = match_result.depth,
                    .value = value,
                    .incoming_nodes = std.ArrayList(*const Lattice.Node).init(allocator),
                    .lowest_incoming_node = null,
                    .cost = 0,
                });
            }
        }

        const first_char = (start_it.nextCodepointSlice()).?;

        // add an unknown node
        if (matches.items.len == 0) {
            try lattice.addNode(.{
                .special_node = false,
                .start_pos = start_pos + 1,
                .length = 1,
                // TODO: we need the unkown data for the proper cost!!!!
                .value = .{ .word = first_char, .cost = 10000 },
                .incoming_nodes = std.ArrayList(*const Lattice.Node).init(allocator),
                .lowest_incoming_node = null,
                .cost = 0,
            });
        }
    }

    return lattice;
}
