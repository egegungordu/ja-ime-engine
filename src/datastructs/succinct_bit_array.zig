const std = @import("std");
const mem = std.mem;
const BitArray = @import("BitArray.zig");

const word_size = @sizeOf(usize);

/// chunk_size is in bytes
pub fn SuccinctBitArrayBuilder(comptime chunk_size: usize) type {
    if (chunk_size < word_size) {
        @compileError("chunk_size must be bigger than " ++ std.fmt.comptimePrint("{}", .{word_size}));
    }
    if ((chunk_size & (chunk_size - 1)) != 0) {
        @compileError("chunk_size must be a power of 2");
    }

    return struct {
        allocator: mem.Allocator,
        bit_array: ?BitArray,
        index: ?std.ArrayList(usize),
        was_built: bool,

        const Self = @This();

        pub fn init(allocator: mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .bit_array = BitArray.init(allocator),
                .index = std.ArrayList(usize).init(allocator),
                .was_built = false,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.bit_array != null) {
                self.bit_array.?.deinit();
            }
            if (self.index != null) {
                self.index.?.deinit();
            }
        }

        pub fn append(self: *Self, bit: u1) !void {
            if (self.was_built) {
                @panic("build was already called");
            }
            if (self.bit_array != null) {
                try self.bit_array.?.append(bit);
            }
        }

        pub fn build(self: *Self) !SuccinctBitArray(chunk_size) {
            if (self.was_built) {
                @panic("build was already called");
            }
            try self.build_index();
            self.was_built = true;

            const bit_array = SuccinctBitArray(chunk_size).init(self.bit_array.?, self.index.?);
            self.bit_array = null;
            self.index = null;
            return bit_array;
        }

        fn build_index(self: *Self) !void {
            const len = self.bit_array.?.bytes.items.len;
            const num_bytes_minus_one: usize = if (len == 0) 0 else len - 1;
            try self.index.?.ensureTotalCapacity(num_bytes_minus_one / chunk_size + 1);
            var i: usize = 0;
            var bit_count: u32 = 0;
            var remaining_words: usize = num_bytes_minus_one / word_size;
            while (remaining_words > 0) : ({
                remaining_words -= @min(chunk_size / word_size, remaining_words);
                i += 1;
            }) {
                const start = chunk_size * i;
                const end = @min(num_bytes_minus_one, start + chunk_size);
                const word_bytes = self.bit_array.?.bytes.items[start..end];
                try self.index.?.append(bit_count);
                const uChunkSize = @Type(.{ .Int = .{ .bits = chunk_size * 8, .signedness = .unsigned } });
                const pop_count = blk: {
                    if (end - start < chunk_size) {
                        var buf: [chunk_size]u8 = .{0} ** chunk_size;
                        @memcpy(buf[0 .. end - start], word_bytes);
                        break :blk @popCount(std.mem.bytesToValue(uChunkSize, &buf));
                    } else {
                        break :blk @popCount(std.mem.bytesToValue(uChunkSize, word_bytes));
                    }
                };
                bit_count += pop_count;
            }
            try self.index.?.append(bit_count);
        }
    };
}

pub fn SuccinctBitArray(comptime chunk_size: usize) type {
    return struct {
        bit_array: BitArray,
        index: std.ArrayList(usize),

        const Self = @This();

        pub fn init(bit_array: BitArray, index: std.ArrayList(usize)) Self {
            return .{
                .bit_array = bit_array,
                .index = index,
            };
        }

        pub fn deinit(self: *Self) void {
            self.bit_array.deinit();
            self.index.deinit();
        }

        pub fn format(self: Self, _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            for (self.bit_array.bytes.items, 0..) |b, i| {
                const remaining: usize = @min(8, self.bit_array.bit_len - i * 8);
                for (0..remaining) |j| {
                    // why it should be u3: https://github.com/ziglang/zig/issues/7605
                    const shift_by: u3 = @truncate(j);
                    try writer.print("{any}", .{@as(u1, @truncate(b >> shift_by))});
                }
            }
        }

        /// Returns the number of 0 bits up to the i-th bit (1-based index)
        pub fn rank0(self: Self, i: usize) !usize {
            if (i >= self.bit_array.bit_len) {
                return error.IndexOutOfBounds;
            }

            return i + 1 - try self.rank1(i);
        }

        /// Returns the number of 1 bits up to the i-th bit (1-based index)
        pub fn rank1(self: Self, i: usize) !usize {
            if (i >= self.bit_array.bit_len) {
                return error.IndexOutOfBounds;
            }

            const chunk_index = i / (chunk_size * 8);

            // find the indexed rank up to the chunk
            var rank = self.index.items[chunk_index];

            // then find the additional rank from the chunk start
            // to the start of the byte containing the i-th bit
            const start = chunk_index * chunk_size;
            const end: usize = i / 8;
            const chunk_bytes = self.bit_array.bytes.items[start..end];
            for (chunk_bytes) |b| {
                rank += @popCount(b);
            }

            // then find the additional rank from the byte containing the i-th bit
            // to the end of the byte
            const last_byte: u8 = self.bit_array.bytes.items[end];
            const shift_by: u3 = 7 - @as(u3, @truncate(i % 8));
            rank += @popCount(@bitReverse(last_byte) >> shift_by);

            return rank;
        }

        /// Returns the position of the i-th 0 bit (1-based index)
        pub fn select0(self: Self, i: usize) !usize {
            if (i == 0) {
                return error.ZeroNotAllowed;
            }

            // Binary search to find the chunk containing the target bit
            var chunk_start: usize = i / (chunk_size * 8);
            var chunk_end: usize = self.index.items.len - 1;
            while (chunk_start <= chunk_end) {
                const chunk_mid = chunk_start + (chunk_end - chunk_start) / 2;
                const zeros_before_chunk = chunk_mid * chunk_size * 8 - self.index.items[chunk_mid];
                if (zeros_before_chunk < i) {
                    chunk_start = chunk_mid + 1;
                } else {
                    chunk_end = chunk_mid - 1;
                }
            }

            // Linear scan within the chunk to find the byte containing the target bit
            const target_chunk = chunk_start - 1;
            const zeros_before_target_chunk = target_chunk * chunk_size * 8 - self.index.items[target_chunk];
            var remaining_zeros: i32 = @intCast(i - zeros_before_target_chunk);
            var bytes = self.bit_array.bytes.items[target_chunk * chunk_size ..];
            var byte_offset: usize = 0;
            while (true) : (bytes = bytes[1..]) {
                if (bytes.len == 0) {
                    return error.IthZeroNotFound;
                }
                const byte = bytes[0];
                const zeros_in_byte = 8 - @popCount(byte);
                remaining_zeros -= zeros_in_byte;
                if (remaining_zeros <= 0) {
                    remaining_zeros += zeros_in_byte;
                    break;
                }
                byte_offset += 1;
            }

            return try self.findBitIndex(target_chunk, byte_offset, remaining_zeros, 0);
        }

        /// Returns the position of the i-th 1 bit (1-based index)
        pub fn select1(self: Self, i: usize) !usize {
            if (i == 0) {
                return error.ZeroNotAllowed;
            }

            // Binary search to find the chunk containing the target bit
            var chunk_start: usize = i / (chunk_size * 8);
            var chunk_end: usize = self.index.items.len - 1;
            while (chunk_start <= chunk_end) {
                const chunk_mid = chunk_start + (chunk_end - chunk_start) / 2;
                const ones_before_chunk = self.index.items[chunk_mid];
                if (ones_before_chunk < i) {
                    chunk_start = chunk_mid + 1;
                } else {
                    chunk_end = chunk_mid - 1;
                }
            }

            // Linear scan within the chunk to find the byte containing the target bit
            const target_chunk = chunk_start - 1;
            const ones_before_target_chunk = self.index.items[target_chunk];
            var remaining_ones: i32 = @intCast(i - ones_before_target_chunk);
            var bytes = self.bit_array.bytes.items[target_chunk * chunk_size ..];
            var byte_offset: usize = 0;
            while (true) : (bytes = bytes[1..]) {
                if (bytes.len == 0) {
                    return error.IthOneNotFound;
                }
                const byte = bytes[0];
                const ones_in_byte = @popCount(byte);
                remaining_ones -= ones_in_byte;
                if (remaining_ones <= 0) {
                    remaining_ones += ones_in_byte;
                    break;
                }
                byte_offset += 1;
            }

            return try self.findBitIndex(target_chunk, byte_offset, remaining_ones, 1);
        }

        pub fn getBit(self: Self, i: usize) !u1 {
            return self.bit_array.get(i);
        }

        /// Find the exact bit position within a byte for the remaining target bits
        fn findBitIndex(self: Self, chunk_index: usize, byte_offset: usize, remaining_count: i32, target_bit: u1) !usize {
            const byte = self.bit_array.bytes.items[chunk_index * chunk_size + byte_offset];
            var bit_pos: usize = 0;
            var bits_to_find = remaining_count;

            // Don't scan past the actual length of the bit array
            const valid_bits = @min(8, self.bit_array.bit_len - (chunk_index * chunk_size * 8 + byte_offset * 8));
            while (bits_to_find > 0 and bit_pos < valid_bits) : (bit_pos += 1) {
                const bit = @as(u1, @truncate(byte >> @truncate(bit_pos)));
                if (bit == target_bit) {
                    bits_to_find -= 1;
                }
            }

            if (bits_to_find > 0) {
                return if (target_bit == 1) error.IthOneNotFound else error.IthZeroNotFound;
            }

            return chunk_index * chunk_size * 8 + byte_offset * 8 + bit_pos - 1;
        }
    };
}
