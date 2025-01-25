const std = @import("std");
const testing = std.testing;

const datastructs = @import("datastructs");
const SuccinctBitArrayBuilder = datastructs.succinct_bit_array.SuccinctBitArrayBuilder;

const test_chunk_sizes = [_]usize{ 8, 16, 32, 64, 128 };

test "succinct bit array: simple rank0" {
    inline for (test_chunk_sizes) |chunk_size| {
        var builder = SuccinctBitArrayBuilder(chunk_size).init(testing.allocator);
        defer builder.deinit();
        try builder.append(1);
        try builder.append(0);
        try builder.append(1);
        try builder.append(1);
        var array = try builder.build();
        defer array.deinit();
        try testing.expectEqual(0, array.rank0(0));
        try testing.expectEqual(1, array.rank0(1));
        try testing.expectEqual(1, array.rank0(2));
        try testing.expectEqual(1, array.rank0(3));
    }
}

test "succinct bit array: long rank0" {
    inline for (test_chunk_sizes) |chunk_size| {
        var builder = SuccinctBitArrayBuilder(chunk_size).init(testing.allocator);
        defer builder.deinit();
        for (0..1024) |_| {
            try builder.append(1);
            try builder.append(1);
            try builder.append(0);
            try builder.append(0);
        }
        var array = try builder.build();
        defer array.deinit();
        for (0..1024) |i| {
            try testing.expectEqual(i * 2, array.rank0(i * 4));
            try testing.expectEqual(i * 2, array.rank0(i * 4 + 1));
            try testing.expectEqual(i * 2 + 1, array.rank0(i * 4 + 2));
            try testing.expectEqual(i * 2 + 2, array.rank0(i * 4 + 3));
        }
    }
}

test "succinct bit array: rank0 out of bounds" {
    inline for (test_chunk_sizes) |chunk_size| {
        var builder = SuccinctBitArrayBuilder(chunk_size).init(testing.allocator);
        defer builder.deinit();
        var array = try builder.build();
        defer array.deinit();
        try testing.expectError(error.IndexOutOfBounds, array.rank0(1024));
    }
}

test "succinct bit array: simple rank1" {
    inline for (test_chunk_sizes) |chunk_size| {
        var builder = SuccinctBitArrayBuilder(chunk_size).init(testing.allocator);
        defer builder.deinit();
        try builder.append(1);
        try builder.append(0);
        try builder.append(1);
        try builder.append(1);
        var array = try builder.build();
        defer array.deinit();
        try testing.expectEqual(1, array.rank1(0));
        try testing.expectEqual(1, array.rank1(1));
        try testing.expectEqual(2, array.rank1(2));
        try testing.expectEqual(3, array.rank1(3));
    }
}

test "succinct bit array: long rank1" {
    inline for (test_chunk_sizes) |chunk_size| {
        var builder = SuccinctBitArrayBuilder(chunk_size).init(testing.allocator);
        defer builder.deinit();

        for (0..1024) |_| {
            try builder.append(1);
            try builder.append(1);
            try builder.append(0);
            try builder.append(0);
        }

        var array = try builder.build();
        defer array.deinit();

        for (0..1024) |i| {
            try testing.expectEqual((i + 1) * 2 - 1, array.rank1(i * 4));
            try testing.expectEqual((i + 1) * 2, array.rank1(i * 4 + 1));
            try testing.expectEqual((i + 1) * 2, array.rank1(i * 4 + 2));
            try testing.expectEqual((i + 1) * 2, array.rank1(i * 4 + 3));
        }
    }
}

test "succinct bit array: rank1 out of bounds" {
    inline for (test_chunk_sizes) |chunk_size| {
        var builder = SuccinctBitArrayBuilder(chunk_size).init(testing.allocator);
        defer builder.deinit();
        var array = try builder.build();
        defer array.deinit();
        try testing.expectError(error.IndexOutOfBounds, array.rank1(1024));
    }
}

test "succinct bit array: simple select1" {
    inline for (test_chunk_sizes) |chunk_size| {
        var builder = SuccinctBitArrayBuilder(chunk_size).init(testing.allocator);
        defer builder.deinit();
        try builder.append(1);
        try builder.append(0);
        try builder.append(1);
        try builder.append(1);
        var array = try builder.build();
        defer array.deinit();
        try testing.expectEqual(0, array.select1(1));
        try testing.expectEqual(2, array.select1(2));
        try testing.expectEqual(3, array.select1(3));
    }
}

test "succinct bit array: long select1" {
    inline for (test_chunk_sizes) |chunk_size| {
        var builder = SuccinctBitArrayBuilder(chunk_size).init(testing.allocator);
        defer builder.deinit();
        for (0..1024) |_| {
            try builder.append(1);
            try builder.append(1);
            try builder.append(0);
            try builder.append(0);
        }
        try builder.append(1);
        var array = try builder.build();
        defer array.deinit();

        for (0..1024) |i| {
            try testing.expectEqual(i * 4, array.select1(i * 2 + 1));
            try testing.expectEqual(i * 4 + 1, array.select1(i * 2 + 2));
        }
    }
}

test "succinct bit array: select1 not found" {
    inline for (test_chunk_sizes) |chunk_size| {
        var builder = SuccinctBitArrayBuilder(chunk_size).init(testing.allocator);
        defer builder.deinit();
        var array = try builder.build();
        defer array.deinit();
        try testing.expectError(error.IthOneNotFound, array.select1(1));
    }
}

test "succinct bit array: select1 zero" {
    inline for (test_chunk_sizes) |chunk_size| {
        var builder = SuccinctBitArrayBuilder(chunk_size).init(testing.allocator);
        defer builder.deinit();
        var array = try builder.build();
        defer array.deinit();
        try testing.expectError(error.ZeroNotAllowed, array.select1(0));
    }
}

test "succinct bit array builder: index" {
    const word_size_in_bits = @bitSizeOf(usize);

    inline for (test_chunk_sizes) |chunk_size| {
        inline for ([_]struct { n: usize, e: []const usize }{
            .{ .n = 0, .e = &.{0} },
            .{ .n = 4, .e = &.{0} },
            .{ .n = word_size_in_bits, .e = &.{0} },
            .{ .n = word_size_in_bits + 1, .e = &.{ 0, word_size_in_bits } },
        }) |e| {
            var builder = SuccinctBitArrayBuilder(chunk_size).init(testing.allocator);
            defer builder.deinit();
            for (0..e.n) |_| {
                try builder.append(1);
            }

            var array = try builder.build();
            defer array.deinit();

            try testing.expectEqualSlices(usize, e.e, array.index.items);
        }
    }
}

test "succinct bit array: print format" {
    inline for (test_chunk_sizes) |chunk_size| {
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
            var builder = SuccinctBitArrayBuilder(chunk_size).init(testing.allocator);
            for (in) |c| {
                try builder.append(@truncate(c - '0'));
            }
            var array = try builder.build();
            defer array.deinit();

            var buf: [100]u8 = undefined;
            try testing.expectEqualStrings(in, try std.fmt.bufPrint(&buf, "{}", .{array}));
        }
    }
}

test "succinct bit array: simple select0" {
    inline for (test_chunk_sizes) |chunk_size| {
        var builder = SuccinctBitArrayBuilder(chunk_size).init(testing.allocator);
        defer builder.deinit();
        try builder.append(1);
        try builder.append(0);
        try builder.append(1);
        try builder.append(1);
        try builder.append(0);
        var array = try builder.build();
        defer array.deinit();
        try testing.expectEqual(1, array.select0(1));
        try testing.expectEqual(4, array.select0(2));
    }
}

test "succinct bit array: long select0" {
    inline for (test_chunk_sizes) |chunk_size| {
        var builder = SuccinctBitArrayBuilder(chunk_size).init(testing.allocator);
        defer builder.deinit();
        for (0..1024) |_| {
            try builder.append(1);
            try builder.append(1);
            try builder.append(0);
            try builder.append(0);
        }
        var array = try builder.build();
        defer array.deinit();

        for (0..1024) |i| {
            try testing.expectEqual(i * 4 + 2, array.select0(i * 2 + 1));
            try testing.expectEqual(i * 4 + 3, array.select0(i * 2 + 2));
        }
    }
}

test "succinct bit array: select0 not found" {
    inline for (test_chunk_sizes) |chunk_size| {
        var builder = SuccinctBitArrayBuilder(chunk_size).init(testing.allocator);
        defer builder.deinit();
        try builder.append(1);
        var array = try builder.build();
        defer array.deinit();
        try testing.expectError(error.IthZeroNotFound, array.select0(1));
    }
}

test "succinct bit array: select0 zero" {
    inline for (test_chunk_sizes) |chunk_size| {
        var builder = SuccinctBitArrayBuilder(chunk_size).init(testing.allocator);
        defer builder.deinit();
        var array = try builder.build();
        defer array.deinit();
        try testing.expectError(error.ZeroNotAllowed, array.select0(0));
    }
}
