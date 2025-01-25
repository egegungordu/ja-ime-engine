const std = @import("std");
const mem = std.mem;
const unicode = std.unicode;
const utf8 = @import("utf8.zig");
const Utf8BidirectionalView = utf8.Utf8BidirectionalView;
const Utf8BidirectionalIterator = utf8.Utf8BidirectionalIterator;
const PeekResult = utf8.PeekResult;

buf: std.ArrayList(u8),
cursor: usize,

const Self = @This();

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
    // we know for a fact that this cant throw because we are shrinking
    self.buf.replaceRange(self.cursor, it.i - self.cursor, &.{}) catch unreachable;
}

pub fn deleteBack(self: *Self, n: usize) void {
    var it = self.initializeIteratorAtCursor();
    iterateBack(&it, n);
    // we know for a fact that this cant throw because we are shrinking
    self.buf.replaceRange(it.i, self.cursor - it.i, &.{}) catch unreachable;
    self.cursor = it.i;
}

pub fn replaceBack(self: *Self, n: usize, new_items: []const u8) !void {
    var it = self.initializeIteratorAtCursor();
    iterateBack(&it, n);
    try self.buf.replaceRange(it.i, self.cursor - it.i, new_items);
    self.cursor = it.i + new_items.len;
}

pub fn clear(self: *Self) void {
    self.buf.clearAndFree();
    self.cursor = 0;
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
