const std = @import("std");
const testing = std.testing;

const datastructs = @import("datastructs");
const BitArray = datastructs.BitArray;

test "append" {
    var stack = BitArray.init(testing.allocator);
    defer stack.deinit();

    try stack.append(1);
    try stack.append(0);
    try stack.append(0);
    try stack.append(1);

    try testing.expectEqual(@as(u1, 1), stack.get(0));
    try testing.expectEqual(@as(u1, 0), stack.get(1));
    try testing.expectEqual(@as(u1, 0), stack.get(2));
    try testing.expectEqual(@as(u1, 1), stack.get(3));
}

test "insert" {
    var stack = BitArray.init(testing.allocator);
    defer stack.deinit();

    try stack.insert(0, 1);
    try stack.insert(1, 0);
    try stack.insert(2, 0);
    try stack.insert(3, 1);
    try stack.insert(1, 1);

    try testing.expectEqual(@as(u1, 1), stack.get(0));
    try testing.expectEqual(@as(u1, 1), stack.get(1));
    try testing.expectEqual(@as(u1, 0), stack.get(2));
    try testing.expectEqual(@as(u1, 0), stack.get(3));
    try testing.expectEqual(@as(u1, 1), stack.get(4));
}
