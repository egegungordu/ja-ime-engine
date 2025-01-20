const std = @import("std");
const mem = std.mem;

const SuccinctBitArray = @import("SuccinctBitArray.zig").SuccinctBitArray;
const SuccinctBitArrayBuilder = @import("SuccinctBitArray.zig").SuccinctBitArrayBuilder;

pub fn Louds(comptime chunk_size: usize) type {
    return struct {
        pub const Node = struct {
            /// The index of the edge to the child. If there is no child (the
            /// value at index is 0), it is null. Root is edge index 0
            /// (if it has a child).
            edge_index: ?usize,
            /// The index of the bit in the bit array. Root is index 2
            /// (because of the super root).
            index: usize,
        };

        sba: SuccinctBitArray(chunk_size),

        pub fn init(succint_bit_array: SuccinctBitArray(chunk_size)) Louds(chunk_size) {
            return .{
                .sba = succint_bit_array,
            };
        }

        pub fn deinit(self: *Louds(chunk_size)) void {
            self.sba.deinit();
        }

        pub fn getRoot(self: Louds(chunk_size)) Node {
            _ = self;
            return Node{
                .edge_index = 0,
                .index = 2,
            };
        }

        pub fn isLeaf(self: Louds(chunk_size), node: Node) bool {
            _ = self;
            // or check (bit at the current index) == 0
            return node.edge_index == null;
        }

        // first-child(m) <- select0(rank1(m)) + 1
        pub fn firstChild(self: Louds(chunk_size), node: *Node) !void {
            const rank = try self.sba.rank1(node.index);
            node.index = try self.sba.select0(rank) + 1;
            node.edge_index = if (try self.sba.getBit(node.index) == 0) null else try self.sba.rank1(node.index) - 2;
        }

        // next-sibling(m) <- m + 1
        pub fn nextSibling(self: Louds(chunk_size), node: *Node) void {
            _ = self;
            node.index += 1;
            if (node.edge_index) |_| node.edge_index.? += 1;
        }

        // parent(m) <- select1(rank0(m - 1))
        pub fn parent(self: Louds(chunk_size), node: *Node) !void {
            node.index = try self.sba.select1(try self.sba.rank0(node.index - 1));
            // TODO: dont need this i think?
            // Search left until we find a 0 bit to get the parent's ID
            // var pos = node.index - 1;
            // while (pos > 0) : (pos -= 1) {
            //     const bit = @as(u1, @truncate(self.sba.bit_array.bytes.items[pos / 8] >> @truncate(pos % 8)));
            //     if (bit == 0) {
            //         node.id = try self.sba.rank0(pos) - 1;
            //         return;
            //     }
            // }
            node.edge_index = try self.sba.rank1(node.index) - 2;
        }

        pub fn getNodeByEdgeIndex(self: Louds(chunk_size), edge_index: usize) !Node {
            return Node{
                .edge_index = edge_index,
                .index = try self.sba.select1(edge_index + 2),
            };
        }

        pub fn hasNextSibling(self: Louds(chunk_size), node: Node) !bool {
            return try self.sba.getBit(node.index + 1) == 1;
        }

        pub fn getNodeIndex(self: Louds(chunk_size), node: Node) !usize {
            return try self.sba.rank0(node.index - 1) - 1;
        }
    };
}
// LOUDS encoding (level-order): 10_1110_110_0_10_10_10_0_0_0
//
//            ●10       <- super root
//            |
//           (a)
//            ●1110     <- root { edge_index: 0, node_index: 0, index: 2 }
//           /|\
//          / | \
//         /  |  \
//        /   |   \
//      (b)  (c)  (d)
//      ●110  ●0   ●10  <- level 1
//     / \         |
//   (e) (f)      (g)
//    ●10 ●10      ●0   <- level 2
//    |   |
//   (h) (i)
//    ●0  ●0            <- level 3
//

fn createTestLouds(comptime chunk_size: usize, allocator: mem.Allocator) !Louds(chunk_size) {
    var sbab = SuccinctBitArrayBuilder(chunk_size).init(allocator);
    const bits: u64 = 0b10_1110_110_0_10_10_10_0_0_0;
    var shift: u6 = @truncate(64 - @clz(bits) - 1);
    while (true) {
        try sbab.append(@truncate((bits >> shift) & 1));
        if (shift == 0) break;
        shift -= 1;
    }
    return Louds(chunk_size).init(try sbab.build());
}

const testing = std.testing;

test "louds: first child" {
    const allocator = testing.allocator;
    var louds = try createTestLouds(16, allocator);
    defer louds.deinit();

    var node = louds.getRoot();
    try louds.firstChild(&node);
    try testing.expectEqual(3, node.edge_index);
    try testing.expectEqual(6, node.index);
    try louds.firstChild(&node);
    try testing.expectEqual(6, node.edge_index);
    try testing.expectEqual(12, node.index);
    try louds.firstChild(&node);
    try testing.expectEqual(null, node.edge_index);
    try testing.expectEqual(17, node.index);
}

test "louds: parent" {
    const allocator = testing.allocator;
    var louds = try createTestLouds(16, allocator);
    defer louds.deinit();

    var node = louds.getRoot();
    try louds.firstChild(&node);
    try louds.firstChild(&node);
    try louds.firstChild(&node);
    try louds.parent(&node);
    try testing.expectEqual(6, node.edge_index);
    try testing.expectEqual(12, node.index);
    try louds.parent(&node);
    try testing.expectEqual(3, node.edge_index);
    try testing.expectEqual(6, node.index);
    try louds.parent(&node);
    try testing.expectEqual(0, node.edge_index);
    try testing.expectEqual(2, node.index);
}

test "louds: next sibling" {
    const allocator = testing.allocator;
    var louds = try createTestLouds(16, allocator);
    defer louds.deinit();

    var node = louds.getRoot();
    try testing.expectEqual(0, node.edge_index);
    try testing.expectEqual(2, node.index);
    try louds.firstChild(&node);
    try testing.expectEqual(3, node.edge_index);
    try testing.expectEqual(6, node.index);
    try louds.parent(&node);
    louds.nextSibling(&node);
    try louds.firstChild(&node);
    try testing.expectEqual(null, node.edge_index);
    try testing.expectEqual(9, node.index);
    try louds.parent(&node);
    louds.nextSibling(&node);
    try louds.firstChild(&node);
    try testing.expectEqual(5, node.edge_index);
    try testing.expectEqual(10, node.index);
}

test "louds: get node index" {
    const allocator = testing.allocator;
    var louds = try createTestLouds(16, allocator);
    defer louds.deinit();

    var node = louds.getRoot();
    try testing.expectEqual(0, try louds.getNodeIndex(node));
    try louds.firstChild(&node);
    try testing.expectEqual(1, try louds.getNodeIndex(node));
    try louds.parent(&node);
    louds.nextSibling(&node);
    try louds.firstChild(&node);
    try testing.expectEqual(2, try louds.getNodeIndex(node));
    try louds.parent(&node);
    louds.nextSibling(&node);
    try louds.firstChild(&node);
    try testing.expectEqual(3, try louds.getNodeIndex(node));
    try louds.firstChild(&node);
    try testing.expectEqual(6, try louds.getNodeIndex(node));
}
