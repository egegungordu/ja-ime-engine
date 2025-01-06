const std = @import("std");
const mem = std.mem;
const unicode = std.unicode;
const testing = std.testing;
const Utf8BidirectionalView = @import("utf8.zig").Utf8BidirectionalView;

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

pub fn insert(self: *Self, s: []const u8) !void {
    try self.buf.insertSlice(self.cursor, s);
    self.cursor += s.len;
}

pub fn moveCursorForward(self: *Self, n: usize) void {
    const view = Utf8BidirectionalView.initUnchecked(self.buf.items);
    var it = view.iterator();
    it.i = self.cursor;
    for (0..n) |_| {
        _ = it.nextCodepoint();
    }
    self.cursor = it.i;
}

pub fn moveCursorBack(self: *Self, n: usize) void {
    const view = Utf8BidirectionalView.initUnchecked(self.buf.items);
    var it = view.iterator();
    it.i = self.cursor;
    for (0..n) |_| {
        _ = it.prevCodepoint();
    }
    self.cursor = it.i;
}

pub fn peekForward(self: *Self, n: usize) []const u8 {
    const view = Utf8BidirectionalView.initUnchecked(self.buf.items);
    var it = view.iterator();
    it.i = self.cursor;
    return it.peekForward(n);
}

pub fn peekBack(self: *Self, n: usize) []const u8 {
    const view = Utf8BidirectionalView.initUnchecked(self.buf.items);
    var it = view.iterator();
    it.i = self.cursor;
    return it.peekBack(n);
}

pub fn deleteForward(self: *Self, n: usize) void {
    const view = Utf8BidirectionalView.initUnchecked(self.buf.items);
    var it = view.iterator();
    it.i = self.cursor;
    for (0..n) |_| {
        _ = it.nextCodepoint();
    }
    self.buf.replaceRangeAssumeCapacity(self.cursor, it.i - self.cursor, &.{});
}

pub fn deleteBack(self: *Self, n: usize) void {
    const view = Utf8BidirectionalView.initUnchecked(self.buf.items);
    var it = view.iterator();
    it.i = self.cursor;
    for (0..n) |_| {
        _ = it.prevCodepoint();
    }
    self.buf.replaceRangeAssumeCapacity(it.i, self.cursor - it.i, &.{});
    self.cursor = it.i;
}

test "utf8 input insert and move cursor" {
    var utf8_input = Self.init(std.testing.allocator);
    defer utf8_input.deinit();

    try utf8_input.insert("こんにちは");
    try utf8_input.insert("世界");
    utf8_input.moveCursorBack(2);
    try utf8_input.insert(", 素晴らしい");
    utf8_input.moveCursorBack(999);
    try utf8_input.insert("はーい");

    try testing.expectEqualStrings("はーいこんにちは, 素晴らしい世界", utf8_input.buf.items);
}

test "utf8 input insert, move cursor and peek" {
    var utf8_input = Self.init(std.testing.allocator);
    defer utf8_input.deinit();

    try utf8_input.insert("こんにちは");
    try utf8_input.insert("世界");
    utf8_input.moveCursorBack(2);

    try testing.expectEqualStrings("世", utf8_input.peekForward(1));
    try testing.expectEqualStrings("世界", utf8_input.peekForward(2));
    try testing.expectEqualStrings("は", utf8_input.peekBack(1));
    try testing.expectEqualStrings("ちは", utf8_input.peekBack(2));

    utf8_input.moveCursorForward(999);
    try testing.expectEqualStrings("こんにちは世界", utf8_input.peekBack(999));
}

test "utf8 input delete" {
    var utf8_input = Self.init(std.testing.allocator);
    defer utf8_input.deinit();

    try utf8_input.insert("こんにちは");

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
