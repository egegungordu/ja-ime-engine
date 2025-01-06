const std = @import("std");
const mem = std.mem;
const unicode = std.unicode;
const testing = std.testing;
const utf8 = @import("utf8.zig");
const Utf8BidirectionalView = utf8.Utf8BidirectionalView;
const Utf8BidirectionalIterator = utf8.Utf8BidirectionalIterator;
const PeekResult = utf8.PeekResult;

const Self = @This();

buf: std.ArrayList(u8),
cursor: usize,

pub fn init(allocator: mem.Allocator) Self {
    return .{
        .buf = std.ArrayList(u8).init(allocator),
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

pub fn deleteForward(self: *Self, n: usize) void {
    var it = self.initializeIteratorAtCursor();
    iterateForward(&it, n);
    self.buf.replaceRangeAssumeCapacity(self.cursor, it.i - self.cursor, &.{});
}

pub fn deleteBack(self: *Self, n: usize) void {
    var it = self.initializeIteratorAtCursor();
    iterateBack(&it, n);
    self.buf.replaceRangeAssumeCapacity(it.i, self.cursor - it.i, &.{});
    self.cursor = it.i;
}

pub fn replaceBack(self: *Self, n: usize, new_items: []const u8) !void {
    var it = self.initializeIteratorAtCursor();
    iterateBack(&it, n);
    try self.buf.replaceRange(it.i, self.cursor - it.i, new_items);
    self.cursor = it.i + new_items.len;
}

fn initializeIteratorAtCursor(self: *Self) Utf8BidirectionalIterator {
    const view = Utf8BidirectionalView.initUnchecked(self.buf.items);
    var it = view.iterator();
    it.i = self.cursor;
    return it;
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

test "utf8 input insert valid/invalid" {
    var utf8_input = Self.init(std.testing.allocator);
    defer utf8_input.deinit();

    try utf8_input.insert("a");
    try testing.expectEqualStrings("a", utf8_input.buf.items);
    try testing.expectError(error.InvalidUtf8, utf8_input.insert(&.{ 0x80, 0x80 }));
    try testing.expectError(error.ExpectedSingleCodepoint, utf8_input.insert("こんにちは世界"));
}

/// Helper function used in testing to insert multiple codepoints.
fn ins(utf8_input: *Self, s: []const u8) !void {
    var it = Utf8BidirectionalView.initUnchecked(s).iterator();
    while (it.nextCodepointSlice()) |codepoint| {
        try utf8_input.insert(codepoint);
    }
}

test "utf8 input insert and move cursor" {
    var utf8_input = Self.init(std.testing.allocator);
    defer utf8_input.deinit();

    try ins(&utf8_input, "こんにちは");
    try ins(&utf8_input, "世界");
    utf8_input.moveCursorBack(2);
    try ins(&utf8_input, ", 素晴らしい");
    utf8_input.moveCursorBack(999);
    try ins(&utf8_input, "はーい");

    try testing.expectEqualStrings("はーいこんにちは, 素晴らしい世界", utf8_input.buf.items);
}

test "utf8 input insert, move cursor and peek" {
    var utf8_input = Self.init(std.testing.allocator);
    defer utf8_input.deinit();

    try ins(&utf8_input, "こんにちは");
    try ins(&utf8_input, "世界");
    utf8_input.moveCursorBack(2);

    try testing.expectEqualStrings("世", utf8_input.peekForward(1).slice);
    try testing.expectEqualStrings("世界", utf8_input.peekForward(2).slice);
    try testing.expectEqualStrings("は", utf8_input.peekBack(1).slice);
    try testing.expectEqualStrings("ちは", utf8_input.peekBack(2).slice);

    utf8_input.moveCursorForward(999);
    try testing.expectEqualStrings("こんにちは世界", utf8_input.peekBack(999).slice);
}

test "utf8 input delete" {
    var utf8_input = Self.init(std.testing.allocator);
    defer utf8_input.deinit();

    try ins(&utf8_input, "こんにちは");

    utf8_input.deleteBack(2);
    try testing.expectEqualStrings("こんに", utf8_input.buf.items);
    utf8_input.moveCursorBack(2);
    utf8_input.deleteForward(1);
    try testing.expectEqualStrings("こに", utf8_input.buf.items);
    utf8_input.deleteForward(999);
    try testing.expectEqualStrings("こ", utf8_input.buf.items);
    utf8_input.deleteBack(999);
    try testing.expectEqualStrings("", utf8_input.buf.items);
}
