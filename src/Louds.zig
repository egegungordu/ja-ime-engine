const std = @import("std");
const mem = std.mem;

const SuccinctBitArray = @import("SuccinctBitArray.zig").SuccinctBitArray;
const SuccinctBitArrayBuilder = @import("SuccinctBitArray.zig").SuccinctBitArrayBuilder;

pub fn Louds(comptime chunk_size: usize) type {
    return struct {
        const Node = struct {
            id: usize,
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
                .id = 0,
                .index = 2,
            };
        }

        pub fn isLeaf(self: Louds(chunk_size), node: Node) !bool {
            return try self.sba.getBit(node.index) == 0;
        }

        // first-child(m) <- select0(rank1(m)) + 1
        pub fn firstChild(self: Louds(chunk_size), node: *Node) !void {
            const rank = try self.sba.rank1(node.index);
            node.index = try self.sba.select0(rank) + 1;
            node.id = rank - 1;
        }

        // next-sibling(m) <- m + 1
        pub fn nextSibling(self: Louds(chunk_size), node: *Node) void {
            _ = self;
            node.index += 1;
            node.id += 1;
        }

        // parent(m) <- select1(rank0(m - 1))
        pub fn parent(self: Louds(chunk_size), node: *Node) !void {
            node.index = try self.sba.select1(try self.sba.rank0(node.index - 1));
            // Search left until we find a 0 bit to get the parent's ID
            var pos = node.index - 1;
            while (pos > 0) : (pos -= 1) {
                const bit = @as(u1, @truncate(self.sba.bit_array.bytes.items[pos / 8] >> @truncate(pos % 8)));
                if (bit == 0) {
                    node.id = try self.sba.rank0(pos) - 1;
                    return;
                }
            }
            node.id = 0; // Root node case
        }

        pub fn getNodeById(self: Louds(chunk_size), id: usize) !Node {
            return Node{
                .id = id,
                .index = try self.sba.select0(id + 1) + 1,
            };
        }

        pub fn hasNextSibling(self: Louds(chunk_size), node: Node) !bool {
            return try self.sba.getBit(node.index + 1) == 1;
        }
    };
}
// LOUDS encoding (level-order): 10_1110_110_0_10_10_10_0_0_0
//
//            ●10       <- super root
//            |
//           (a)
//            ●1110     <- root
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

test "what the fuck doude?" {
    var sbab = SuccinctBitArrayBuilder(16).init(std.testing.allocator);
    const bits: u64 = 0b10101010111111110010011100001000000;
    var shift: u6 = @truncate(64 - @clz(bits) - 1);
    while (true) {
        try sbab.append(@truncate((bits >> shift) & 1));
        if (shift == 0) break;
        shift -= 1;
    }
    var louds = Louds(16).init(try sbab.build());
    defer louds.deinit();

    std.debug.print("sba: {any}\n", .{louds.sba});

    var node = try louds.getNodeById(3);
    std.debug.print("node_id: {d}, node_index: {d}\n", .{ node.id, node.index });
    try louds.firstChild(&node);
    std.debug.print("node_id: {d}, node_index: {d}\n", .{ node.id, node.index });
}

test "louds: first child" {
    const allocator = std.testing.allocator;
    var louds = try createTestLouds(16, allocator);
    defer louds.deinit();

    var node = louds.getRoot();
    try louds.firstChild(&node);
    try std.testing.expectEqual(1, node.id);
    try std.testing.expectEqual(6, node.index);
    try louds.firstChild(&node);
    try std.testing.expectEqual(4, node.id);
    try std.testing.expectEqual(12, node.index);
    try louds.firstChild(&node);
    try std.testing.expectEqual(7, node.id);
    try std.testing.expectEqual(17, node.index);
}

test "louds: parent" {
    const allocator = std.testing.allocator;
    var louds = try createTestLouds(16, allocator);
    defer louds.deinit();

    var node = louds.getRoot();
    try louds.firstChild(&node);
    try louds.firstChild(&node);
    try louds.firstChild(&node);
    try louds.parent(&node);
    try std.testing.expectEqual(4, node.id);
    try std.testing.expectEqual(12, node.index);
    try louds.parent(&node);
    try std.testing.expectEqual(1, node.id);
    try std.testing.expectEqual(6, node.index);
    try louds.parent(&node);
    try std.testing.expectEqual(0, node.id);
    try std.testing.expectEqual(2, node.index);
}

test "louds: next sibling" {
    const allocator = std.testing.allocator;
    var louds = try createTestLouds(16, allocator);
    defer louds.deinit();

    var node = louds.getRoot();
    try std.testing.expectEqual(0, node.id);
    try std.testing.expectEqual(2, node.index);
    try louds.firstChild(&node);
    try std.testing.expectEqual(1, node.id);
    try std.testing.expectEqual(6, node.index);
    try louds.parent(&node);
    louds.nextSibling(&node);
    try louds.firstChild(&node);
    try std.testing.expectEqual(2, node.id);
    try std.testing.expectEqual(9, node.index);
    try louds.parent(&node);
    louds.nextSibling(&node);
    try louds.firstChild(&node);
    try std.testing.expectEqual(3, node.id);
    try std.testing.expectEqual(10, node.index);
}
