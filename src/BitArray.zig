const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Self = @This();

bytes: std.ArrayList(u8),
bit_len: usize = 0,

pub fn init(allocator: Allocator) @This() {
    return .{
        .bytes = std.ArrayList(u8).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.bytes.deinit();
    self.* = undefined;
}

pub fn ensureTotalCapacity(self: *Self, bit_capcity: usize) Allocator.Error!void {
    const byte_capacity = (bit_capcity + 7) >> 3;
    try self.bytes.ensureTotalCapacity(byte_capacity);
}

pub fn append(self: *Self, b: u1) Allocator.Error!void {
    const byte_index = self.bit_len >> 3;
    if (self.bytes.items.len <= byte_index) {
        try self.bytes.append(0);
    }

    appendWithStateAssumeCapacity(self.bytes.items, &self.bit_len, b);
}

pub fn insert(self: *Self, index: usize, b: u1) Allocator.Error!void {
    const byte_index = self.bit_len >> 3;
    if (self.bytes.items.len <= byte_index) {
        try self.bytes.append(0);
    }

    insertWithStateAssumeCapacity(self.bytes.items, &self.bit_len, b, index);
}

pub fn get(self: *const Self, index: usize) u1 {
    const byte_index = index >> 3;
    const bit_index = @as(u3, @intCast(index & 7));
    return @as(u1, @intCast((self.bytes.items[byte_index] >> bit_index) & 1));
}

pub fn set(self: *Self, index: usize, b: u1) void {
    const byte_index = index >> 3;
    const bit_index = @as(u3, @intCast(index & 7));
    self.bytes.items[byte_index] &= ~(@as(u8, 1) << bit_index);
    self.bytes.items[byte_index] |= @as(u8, b) << bit_index;
}

pub fn appendWithStateAssumeCapacity(buf: []u8, bit_len: *usize, b: u1) void {
    const byte_index = bit_len.* >> 3;
    const bit_index = @as(u3, @intCast(bit_len.* & 7));

    buf[byte_index] &= ~(@as(u8, 1) << bit_index);
    buf[byte_index] |= @as(u8, b) << bit_index;

    bit_len.* += 1;
}

pub fn insertWithStateAssumeCapacity(buf: []u8, bit_len: *usize, b: u1, index: usize) void {
    // insert will shift all the bits to the right
    const byte_index = index >> 3;
    const bit_index = @as(u3, @intCast(index & 7));

    // before inserting, we need to shift the bits from the insert point to the right
    // also do not lose the last bit.
    var last_bit: u1 = @intCast(buf[byte_index] & 128);
    // shift the bits from the index
    const shifted_bits_mask = @as(u8, 0b1111_1110) << bit_index;
    const shifted_bits: u8 = (buf[byte_index] & shifted_bits_mask) << 1;
    buf[byte_index] &= ~shifted_bits_mask;
    buf[byte_index] |= shifted_bits;

    // insert the new bit
    buf[byte_index] |= @as(u8, b) << bit_index;

    // while we have more bytes in the buffer, we do the same thing
    var i = byte_index + 1;
    while (i < buf.len) : ({
        i += 1;
    }) {
        const temp_last_bit: u1 = @intCast(buf[i] & 128);
        buf[i] = buf[i] << 1;
        buf[i] |= last_bit;
        last_bit = temp_last_bit;
    }

    bit_len.* += 1;
}

const testing = std.testing;
test "append" {
    var stack = Self.init(testing.allocator);
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
    var stack = Self.init(testing.allocator);
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
