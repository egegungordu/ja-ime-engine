const std = @import("std");
const mem = std.mem;
const unicode = std.unicode;
const testing = @import("std").testing;
const Utf8Input = @import("Utf8Input.zig");
const utf8 = @import("utf8.zig");
const trans = @import("transliteration.zig");

const Self = @This();

allocator: std.mem.Allocator,
input: Utf8Input,

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .allocator = allocator,
        .input = Utf8Input.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.input.deinit();
}

pub fn insert(self: *Self, s: []const u8) !void {
    try self.input.insert(s);
    if (self.matchBack(3)) |match| {
        try self.input.replaceBack(3, match.kana);
    } else if (self.matchBack(2)) |match| {
        // If the matched slice is a repeat (e.g. "tt", "mm"),
        // we need to only replace the first half of the slice
        //
        // Example:
        // - wrong:   tt -> っ    (replace two)
        // - correct: tt -> っt   (replace first half only)
        if (areFirstTwoCodepointsSame(match.slice)) {
            self.input.moveCursorBack(1);
            try self.input.replaceBack(1, match.kana);
            self.input.moveCursorForward(1);
        } else {
            try self.input.replaceBack(2, match.kana);
        }
    } else if (self.matchBack(1)) |match| {
        try self.input.replaceBack(1, match.kana);
    }
}

pub fn moveCursorForward(self: *Self) void {
    self.input.moveCursorForward(1);
}

pub fn moveCursorBack(self: *Self) void {
    self.input.moveCursorBack(1);
}

fn isTransliterable(s: []const u8) bool {
    return trans.transliterables.get(s) != null;
}

fn peekBackTransliterable(self: *Self, n: usize) ?[]const u8 {
    var total_codepoint_len: usize = 0;
    var last_slice: []const u8 = undefined;
    for (0..n) |i| {
        const peeked = self.input.peekBackOne(i);
        if (peeked.codepoint_len == 0 or !isTransliterable(peeked.slice)) {
            return null;
        }
        total_codepoint_len += peeked.codepoint_len;
        last_slice = peeked.slice;
    }
    // Convert the last slice to a raw pointer and back to get the correct slice
    const raw_ptr: [*]const u8 = @ptrCast(last_slice.ptr);
    const corrected_slice = raw_ptr[0..total_codepoint_len];
    return corrected_slice;
}

fn matchKana(s: []const u8) ?[]const u8 {
    return trans.transliteration_map.get(s);
}

const MatchBackResult = struct {
    slice: []const u8,
    kana: []const u8,
};

fn matchBack(self: *Self, n: usize) ?MatchBackResult {
    if (peekBackTransliterable(self, n)) |slice| {
        if (matchKana(slice)) |match| {
            return .{ .slice = slice, .kana = match };
        }
    }
    return null;
}

fn areFirstTwoCodepointsSame(slice: []const u8) bool {
    var view = unicode.Utf8View.initUnchecked(slice);
    var it = view.iterator();

    const first = it.nextCodepoint() orelse return false;
    const second = it.nextCodepoint() orelse return false;

    return first == second;
}

test "areFirstTwoCodepointsSame" {
    try testing.expect(areFirstTwoCodepointsSame("aa"));
    try testing.expect(areFirstTwoCodepointsSame("ああ"));
    try testing.expect(!areFirstTwoCodepointsSame("ab"));
    try testing.expect(!areFirstTwoCodepointsSame("a"));
    try testing.expect(!areFirstTwoCodepointsSame(""));
}

test "ime" {
    var ime = Self.init(std.testing.allocator);
    defer ime.deinit();

    for ("mainichishikottemasu,azassunbonbo") |c| {
        try ime.insert(&.{c});
        std.debug.print("{s}\n", .{ime.input.buf.items});
    }
}
