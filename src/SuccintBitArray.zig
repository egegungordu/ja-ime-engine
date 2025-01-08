const std = @import("std");
const mem = std.mem;

const word_size = @sizeOf(usize);

/// chunk_size is in bytes
pub fn SuccintBitArrayBuilder(comptime chunk_size: usize) type {
    if (chunk_size < word_size) {
        @compileError("chunk_size must be bigger than " ++ std.fmt.comptimePrint("{}", .{word_size}));
    }
    if ((chunk_size & (chunk_size - 1)) != 0) {
        @compileError("chunk_size must be a power of 2");
    }

    return struct {
        allocator: mem.Allocator,
        bit_stack: ?std.BitStack,
        index: ?std.ArrayList(usize),
        was_built: bool,

        const Self = @This();

        pub fn init(allocator: mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .bit_stack = std.BitStack.init(allocator),
                .index = std.ArrayList(usize).init(allocator),
                .was_built = false,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.bit_stack != null) {
                self.bit_stack.?.deinit();
            }
            if (self.index != null) {
                self.index.?.deinit();
            }
        }

        pub fn push(self: *Self, bit: u1) !void {
            if (self.was_built) {
                @panic("build was already called");
            }
            if (self.bit_stack != null) {
                try self.bit_stack.?.push(bit);
            }
        }

        pub fn build(self: *Self) !SuccintBitArray(chunk_size) {
            if (self.was_built) {
                @panic("build was already called");
            }
            try self.build_index();
            self.was_built = true;

            const bit_array = SuccintBitArray(chunk_size).init(self.bit_stack.?, self.index.?);
            self.bit_stack = null;
            self.index = null;
            return bit_array;
        }

        fn build_index(self: *Self) !void {
            const len = self.bit_stack.?.bytes.items.len;
            const num_bytes_minus_one: usize = if (len == 0) 0 else len - 1;
            try self.index.?.ensureTotalCapacity(num_bytes_minus_one / chunk_size + 1);
            var i: usize = 0;
            var bit_count: u32 = 0;
            var remaining_words: usize = num_bytes_minus_one / word_size;
            while (remaining_words > 0) : ({
                remaining_words -= chunk_size / word_size;
                i += 1;
            }) {
                const start = chunk_size * i;
                const end = @min(num_bytes_minus_one, start + word_size);
                const word_bytes = self.bit_stack.?.bytes.items[start..end];
                try self.index.?.append(bit_count);
                bit_count += @popCount(std.mem.bytesToValue(usize, word_bytes));
            }
            try self.index.?.append(bit_count);
        }
    };
}

pub fn SuccintBitArray(comptime chunk_size: usize) type {
    return struct {
        bit_stack: std.BitStack,
        index: std.ArrayList(usize),

        const Self = @This();

        pub fn init(bit_stack: std.BitStack, index: std.ArrayList(usize)) Self {
            return .{
                .bit_stack = bit_stack,
                .index = index,
            };
        }

        pub fn deinit(self: *Self) void {
            self.bit_stack.deinit();
            self.index.deinit();
        }

        pub fn format(self: Self, _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            for (self.bit_stack.bytes.items, 0..) |b, i| {
                const remaining: usize = @min(8, self.bit_stack.bit_len - i * 8);
                for (0..remaining) |j| {
                    // why it should be u3: https://github.com/ziglang/zig/issues/7605
                    const shift_by: u3 = @truncate(j);
                    try writer.print("{any}", .{@as(u1, @truncate(b >> shift_by))});
                }
            }
        }

        pub fn rank1(self: *Self, i: usize) usize {
            const chunk_index = i / (chunk_size * 8);

            // find the indexed rank up to the chunk
            var rank = self.index.items[chunk_index];

            // then find the additional rank from the chunk start
            // to the start of the byte containing the i-th bit
            const start = chunk_index * chunk_size;
            const end: usize = i / 8;
            const chunk_bytes = self.bit_stack.bytes.items[start..end];
            for (chunk_bytes) |b| {
                rank += @popCount(b);
            }

            // then find the additional rank from the byte containing the i-th bit
            // to the end of the byte
            const last_byte: u8 = self.bit_stack.bytes.items[end];
            const shift_by: u3 = 7 - @as(u3, @truncate(i % 8));
            rank += @popCount(@bitReverse(last_byte) >> shift_by);

            return rank;
        }

        pub fn rank0(self: *Self, i: usize) usize {
            return i + 1 - self.rank1(i);
        }
    };
}

test "succint bit array: simple rank1" {
    var builder = SuccintBitArrayBuilder(8).init(std.testing.allocator);
    defer builder.deinit();
    try builder.push(1);
    try builder.push(0);
    try builder.push(1);
    try builder.push(1);
    var array = try builder.build();
    defer array.deinit();
    try std.testing.expectEqual(1, array.rank1(0));
    try std.testing.expectEqual(1, array.rank1(1));
    try std.testing.expectEqual(2, array.rank1(2));
    try std.testing.expectEqual(3, array.rank1(3));
}

test "succint bit array: long rank1" {
    var builder = SuccintBitArrayBuilder(8).init(std.testing.allocator);
    defer builder.deinit();

    for (0..1024) |_| {
        try builder.push(1);
        try builder.push(1);
        try builder.push(0);
        try builder.push(0);
    }

    var array = try builder.build();
    defer array.deinit();

    for (0..1024) |i| {
        try std.testing.expectEqual((i + 1) * 2 - 1, array.rank1(i * 4));
        try std.testing.expectEqual((i + 1) * 2, array.rank1(i * 4 + 1));
        try std.testing.expectEqual((i + 1) * 2, array.rank1(i * 4 + 2));
        try std.testing.expectEqual((i + 1) * 2, array.rank1(i * 4 + 3));
    }
}

test "succint bit array: simple rank0" {
    var builder = SuccintBitArrayBuilder(8).init(std.testing.allocator);
    defer builder.deinit();
    try builder.push(1);
    try builder.push(0);
    try builder.push(1);
    try builder.push(1);
    var array = try builder.build();
    defer array.deinit();
    try std.testing.expectEqual(0, array.rank0(0));
    try std.testing.expectEqual(1, array.rank0(1));
    try std.testing.expectEqual(1, array.rank0(2));
    try std.testing.expectEqual(1, array.rank0(3));
}

test "succint bit array: rank0" {
    var builder = SuccintBitArrayBuilder(8).init(std.testing.allocator);
    defer builder.deinit();
    for (0..1024) |_| {
        try builder.push(1);
        try builder.push(1);
        try builder.push(0);
        try builder.push(0);
    }
    var array = try builder.build();
    defer array.deinit();
    for (0..1024) |i| {
        try std.testing.expectEqual(i * 2, array.rank0(i * 4));
        try std.testing.expectEqual(i * 2, array.rank0(i * 4 + 1));
        try std.testing.expectEqual(i * 2 + 1, array.rank0(i * 4 + 2));
        try std.testing.expectEqual(i * 2 + 2, array.rank0(i * 4 + 3));
    }
}

test "succint bit array builder: index" {
    const word_size_in_bits = @bitSizeOf(usize);

    inline for ([_]struct { n: usize, e: []const usize }{
        .{ .n = 0, .e = &.{0} },
        .{ .n = 4, .e = &.{0} },
        .{ .n = word_size_in_bits, .e = &.{0} },
        .{ .n = word_size_in_bits + 1, .e = &.{ 0, word_size_in_bits } },
    }) |e| {
        var builder = SuccintBitArrayBuilder(8).init(std.testing.allocator);
        defer builder.deinit();
        for (0..e.n) |_| {
            try builder.push(1);
        }

        var array = try builder.build();
        defer array.deinit();

        try std.testing.expectEqualSlices(usize, e.e, array.index.items);
    }
}

test "succint bit array: print format" {
    inline for ([_][]const u8{
        "111100101010100111",
        "0000",
        "1111",
        "10101",
        "01010",
        "1",
        "0",
        "",
    }) |in| {
        var builder = SuccintBitArrayBuilder(8).init(std.testing.allocator);
        for (in) |c| {
            try builder.push(@truncate(c - '0'));
        }
        var array = try builder.build();
        defer array.deinit();

        var buf: [100]u8 = undefined;
        try std.testing.expectEqualStrings(in, try std.fmt.bufPrint(&buf, "{}", .{array}));
    }
}
