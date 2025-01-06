const std = @import("std");
const mem = std.mem;
const unicode = std.unicode;
const testing = std.testing;
const utf8 = @import("utf8.zig");
const Utf8BidirectionalView = utf8.Utf8BidirectionalView;
const Utf8BidirectionalIterator = utf8.Utf8BidirectionalIterator;
const PeekResult = utf8.PeekResult;

pub const StorageTag = enum {
    owned,
    borrowed,
};

fn BufferStorage(comptime tag: StorageTag) type {
    return struct {
        data: switch (tag) {
            .owned => std.ArrayList(u8),
            .borrowed => []u8,
        },
        len: if (tag == .borrowed) usize else void,

        const Storage = @This();

        pub fn init(arg: switch (tag) {
            .owned => mem.Allocator,
            .borrowed => []u8,
        }) Storage {
            return switch (tag) {
                .owned => .{
                    .data = std.ArrayList(u8).init(arg),
                    .len = {},
                },
                .borrowed => .{
                    .data = arg,
                    .len = 0,
                },
            };
        }

        pub fn deinit(self: *Storage) void {
            switch (tag) {
                .owned => self.data.deinit(),
                .borrowed => {}, // Nothing to deinit for borrowed memory
            }
        }

        pub fn items(self: *const Storage) []const u8 {
            return switch (tag) {
                .owned => self.data.items,
                .borrowed => self.data[0..self.len],
            };
        }

        pub fn insertSlice(self: *Storage, i: usize, slice: []const u8) !void {
            switch (tag) {
                .owned => try self.data.insertSlice(i, slice),
                .borrowed => {
                    // For borrowed buffers, we need to ensure there's enough space and shift existing data
                    if (i > self.len) return error.OutOfBounds;
                    const required_len = self.len + slice.len;
                    if (required_len > self.data.len) return error.OutOfMemory;

                    // Shift existing data to make room
                    const move_amount = slice.len;
                    const move_start = i;
                    const move_end = self.len;
                    var j: usize = move_end;
                    while (j > move_start) : (j -= 1) {
                        self.data[j + move_amount - 1] = self.data[j - 1];
                    }

                    // Copy new data
                    @memcpy(self.data[i..][0..slice.len], slice);
                    self.len += slice.len;
                },
            }
        }

        pub fn replaceRange(self: *Storage, start: usize, len: usize, new_items: []const u8) !void {
            switch (tag) {
                .owned => try self.data.replaceRange(start, len, new_items),
                .borrowed => {
                    if (start + len > self.len) return error.OutOfBounds;
                    const after_range = start + len;
                    const range_diff = @as(isize, @intCast(new_items.len)) - @as(isize, @intCast(len));

                    if (range_diff > 0) {
                        // Growing: need to shift data right
                        if (self.len + @as(usize, @intCast(range_diff)) > self.data.len) return error.OutOfMemory;
                        var i: usize = self.len - 1;
                        while (i >= after_range) : (i -= 1) {
                            self.data[i + @as(usize, @intCast(range_diff))] = self.data[i];
                            if (i == 0) break;
                        }
                    } else if (range_diff < 0) {
                        // Shrinking: need to shift data left
                        for (after_range..self.len) |i| {
                            self.data[i + @as(usize, @intCast(-range_diff))] = self.data[i];
                        }
                    }

                    @memcpy(self.data[start..][0..new_items.len], new_items);
                    if (range_diff < 0) {
                        self.len = self.len - @as(usize, @intCast(-range_diff));
                    } else {
                        self.len = self.len + @as(usize, @intCast(range_diff));
                    }
                },
            }
        }

        pub fn clear(self: *Storage) void {
            switch (tag) {
                .owned => self.data.clearAndFree(),
                .borrowed => {
                    // For borrowed buffer, we just set all bytes to 0
                    @memset(self.data[0..self.len], 0);
                    self.len = 0;
                },
            }
        }
    };
}

pub fn Utf8Input(comptime tag: StorageTag) type {
    return struct {
        buf: BufferStorage(tag),
        cursor: usize,

        const Self = @This();

        pub fn init(arg: switch (tag) {
            .owned => mem.Allocator,
            .borrowed => []u8,
        }) Self {
            return .{
                .buf = BufferStorage(tag).init(arg),
                .cursor = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            self.buf.deinit();
        }

        /// Insert a single UTF-8 encoded codepoint.
        ///
        /// Checks if the input is a valid UTF-8 sequence and if it is a single codepoint.
        pub fn insert(self: *Self, s: []const u8) !void {
            if (!unicode.utf8ValidateSlice(s)) {
                return error.InvalidUtf8;
            }
            if (try unicode.utf8CountCodepoints(s) != 1) {
                return error.ExpectedSingleCodepoint;
            }
            try self.buf.insertSlice(self.cursor, s);
            self.cursor += s.len;
        }

        pub fn moveCursorForward(self: *Self, n: usize) void {
            var it = self.initializeIteratorAtCursor();
            iterateForward(&it, n);
            self.cursor = it.i;
        }

        pub fn moveCursorBack(self: *Self, n: usize) void {
            var it = self.initializeIteratorAtCursor();
            iterateBack(&it, n);
            self.cursor = it.i;
        }

        // probably name it peekRangeBack/peekRangeForward
        pub fn peekForward(self: *Self, n: usize) PeekResult {
            var it = self.initializeIteratorAtCursor();
            return it.peekForward(n);
        }

        pub fn peekBack(self: *Self, n: usize) PeekResult {
            var it = self.initializeIteratorAtCursor();
            return it.peekBack(n);
        }

        pub fn peekBackOne(self: *Self, n: usize) PeekResult {
            var it = self.initializeIteratorAtCursor();
            iterateBack(&it, n);
            return it.peekBack(1);
        }

        pub fn peekForwardOne(self: *Self, n: usize) PeekResult {
            var it = self.initializeIteratorAtCursor();
            iterateForward(&it, n);
            return it.peekForward(1);
        }

        pub fn deleteForward(self: *Self, n: usize) !void {
            var it = self.initializeIteratorAtCursor();
            iterateForward(&it, n);
            try self.buf.replaceRange(self.cursor, it.i - self.cursor, &.{});
        }

        pub fn deleteBack(self: *Self, n: usize) !void {
            var it = self.initializeIteratorAtCursor();
            iterateBack(&it, n);
            try self.buf.replaceRange(it.i, self.cursor - it.i, &.{});
            self.cursor = it.i;
        }

        pub fn replaceBack(self: *Self, n: usize, new_items: []const u8) !void {
            var it = self.initializeIteratorAtCursor();
            iterateBack(&it, n);
            try self.buf.replaceRange(it.i, self.cursor - it.i, new_items);
            self.cursor = it.i + new_items.len;
        }

        pub fn clear(self: *Self) void {
            self.buf.clear();
            self.cursor = 0;
        }

        fn initializeIteratorAtCursor(self: *Self) Utf8BidirectionalIterator {
            const view = Utf8BidirectionalView.initUnchecked(self.buf.items());
            var it = view.iterator();
            it.i = self.cursor;
            return it;
        }
    };
}

fn iterateForward(it: *Utf8BidirectionalIterator, n: usize) void {
    for (0..n) |_| {
        _ = it.nextCodepoint();
    }
}

fn iterateBack(it: *Utf8BidirectionalIterator, n: usize) void {
    for (0..n) |_| {
        _ = it.prevCodepoint();
    }
}

// Owned buffer tests
test "utf8 input: owned - basic validation" {
    var utf8_input = Utf8Input(.owned).init(std.testing.allocator);
    defer utf8_input.deinit();

    try utf8_input.insert("a");
    try testing.expectEqualStrings("a", utf8_input.buf.items());
    try testing.expectError(error.InvalidUtf8, utf8_input.insert(&.{ 0x80, 0x80 }));
    try testing.expectError(error.ExpectedSingleCodepoint, utf8_input.insert("こんにちは世界"));
}

test "utf8 input: owned - cursor movement" {
    var utf8_input = Utf8Input(.owned).init(std.testing.allocator);
    defer utf8_input.deinit();

    try ins(.owned, &utf8_input, "こんにちは");
    try ins(.owned, &utf8_input, "世界");
    utf8_input.moveCursorBack(2);
    try ins(.owned, &utf8_input, ", 素晴らしい");
    utf8_input.moveCursorBack(999);
    try ins(.owned, &utf8_input, "はーい");

    try testing.expectEqualStrings("はーいこんにちは, 素晴らしい世界", utf8_input.buf.items());
}

test "utf8 input: owned - peek operations" {
    var utf8_input = Utf8Input(.owned).init(std.testing.allocator);
    defer utf8_input.deinit();

    try ins(.owned, &utf8_input, "こんにちは");
    try ins(.owned, &utf8_input, "世界");
    utf8_input.moveCursorBack(2);

    try testing.expectEqualStrings("世", utf8_input.peekForward(1).slice);
    try testing.expectEqualStrings("世界", utf8_input.peekForward(2).slice);
    try testing.expectEqualStrings("は", utf8_input.peekBack(1).slice);
    try testing.expectEqualStrings("ちは", utf8_input.peekBack(2).slice);

    utf8_input.moveCursorForward(999);
    try testing.expectEqualStrings("こんにちは世界", utf8_input.peekBack(999).slice);
}

test "utf8 input: owned - delete operations" {
    var utf8_input = Utf8Input(.owned).init(std.testing.allocator);
    defer utf8_input.deinit();

    try ins(.owned, &utf8_input, "こんにちは");

    try utf8_input.deleteBack(2);
    try testing.expectEqualStrings("こんに", utf8_input.buf.items());
    utf8_input.moveCursorBack(2);
    try utf8_input.deleteForward(1);
    try testing.expectEqualStrings("こに", utf8_input.buf.items());
    try utf8_input.deleteForward(999);
    try testing.expectEqualStrings("こ", utf8_input.buf.items());
    try utf8_input.deleteBack(999);
    try testing.expectEqualStrings("", utf8_input.buf.items());
}

// Borrowed buffer tests
test "utf8 input: borrowed - basic operations" {
    var buf: [100]u8 = undefined;
    var utf8_input = Utf8Input(.borrowed).init(&buf);
    defer utf8_input.deinit();

    try utf8_input.insert("a");
    try testing.expectEqualStrings("a", utf8_input.buf.items());
    try utf8_input.insert("b");
    try testing.expectEqualStrings("ab", utf8_input.buf.items());
    try utf8_input.deleteBack(1);
    try testing.expectEqualStrings("a", utf8_input.buf.items());
}

test "utf8 input: borrowed - replace range" {
    var buf: [100]u8 = undefined;
    var utf8_input = Utf8Input(.borrowed).init(&buf);
    defer utf8_input.deinit();

    try utf8_input.insert("a");
    try utf8_input.insert("b");
    try utf8_input.replaceBack(1, "c");
    try testing.expectEqualStrings("ac", utf8_input.buf.items());
}

test "utf8 input: borrowed - cursor movement" {
    var buf: [100]u8 = undefined;
    var utf8_input = Utf8Input(.borrowed).init(&buf);
    defer utf8_input.deinit();

    try utf8_input.insert("a");
    try utf8_input.insert("b");
    try utf8_input.insert("c");
    utf8_input.moveCursorBack(2);
    try utf8_input.insert("d");
    try testing.expectEqualStrings("adbc", utf8_input.buf.items());
}

test "utf8 input: borrowed - buffer overflow" {
    var small_buf: [3]u8 = undefined;
    var utf8_input = Utf8Input(.borrowed).init(&small_buf);
    defer utf8_input.deinit();

    try utf8_input.insert("a");
    try utf8_input.insert("b");
    try utf8_input.insert("c");
    try testing.expectError(error.OutOfMemory, utf8_input.insert("d"));
}

test "utf8 input: borrowed - unicode handling" {
    var buf: [100]u8 = undefined;
    var utf8_input = Utf8Input(.borrowed).init(&buf);
    defer utf8_input.deinit();

    try utf8_input.insert("あ");
    try testing.expectEqualStrings("あ", utf8_input.buf.items());
    try utf8_input.insert("い");
    try testing.expectEqualStrings("あい", utf8_input.buf.items());
    utf8_input.moveCursorBack(1);
    try utf8_input.insert("う");
    try testing.expectEqualStrings("あうい", utf8_input.buf.items());
}

test "utf8 input: borrowed - clear buffer" {
    var buf: [10]u8 = undefined;
    @memset(&buf, 'x');
    var utf8_input = Utf8Input(.borrowed).init(&buf);
    defer utf8_input.deinit();

    try utf8_input.insert("a");
    try utf8_input.insert("b");
    try testing.expectEqualStrings("ab", utf8_input.buf.items());
    utf8_input.clear();
    try testing.expectEqualStrings("", utf8_input.buf.items());
}

/// Helper function used in testing to insert multiple codepoints.
fn ins(comptime tag: StorageTag, utf8_input: *Utf8Input(tag), s: []const u8) !void {
    var it = Utf8BidirectionalView.initUnchecked(s).iterator();
    while (it.nextCodepointSlice()) |codepoint| {
        try utf8_input.insert(codepoint);
    }
}
