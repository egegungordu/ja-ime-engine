const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const datastructs = @import("datastructs");
const Louds = datastructs.louds.Louds;
const SuccinctBitArrayBuilder = datastructs.succinct_bit_array.SuccinctBitArrayBuilder;

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

pub fn createTestLouds(comptime chunk_size: usize, allocator: mem.Allocator) !Louds(chunk_size) {
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
