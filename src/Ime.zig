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

/// Inserts a slice into the input buffer, doing transliteration if possible.
/// Only accepts one valid UTF-8 codepoint at a time.
pub fn insert(self: *Self, s: []const u8) !void {
    try self.input.insert(s);
    if (self.matchBack(4)) |match| {
        switch (match.original_codepoint_len) {
            2 => {
                // Special case for two codepoints:
                //  If the matched slice is a repeat (e.g. "tt", "mm", except for "nn"),
                //  we need to only replace the first half of the slice
                //
                // Example:
                // - wrong:   tt -> っ    (replace two)
                // - correct: tt -> っt   (replace first half only)
                if (match.original_slice[0] != 'n' and areFirstTwoCodepointsSame(match.original_slice)) {
                    self.input.moveCursorBack(1);
                    try self.input.replaceBack(1, match.matched_slice);
                    self.input.moveCursorForward(1);
                } else {
                    try self.input.replaceBack(2, match.matched_slice);
                }
            },
            else => try self.input.replaceBack(match.original_codepoint_len, match.matched_slice),
        }
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
const PeekBackTransliterableResult = struct {
    slice: []const u8,
    codepoint_len: usize,
};

/// Peeks back n characters in the input buffer and returns the biggest transliterable slice.
///
/// Example (n = 2):
/// - hello -> .{ "lo", "2" }
/// - んg -> .{ "g", "1" }
fn peekBackTransliterable(self: *Self, n: usize) ?PeekBackTransliterableResult {
    var total_bytes: usize = 0;
    var total_codepoint_len: usize = 0;
    var last_slice: []const u8 = undefined;
    for (0..n) |i| {
        const peeked = self.input.peekBackOne(i);
        if (peeked.codepoint_len == 0 or !isTransliterable(peeked.slice)) {
            return PeekBackTransliterableResult{
                .slice = @as([*]const u8, @ptrCast(last_slice.ptr))[0..total_bytes],
                .codepoint_len = total_codepoint_len,
            };
        }
        total_codepoint_len += peeked.codepoint_len;
        total_bytes += peeked.slice.len;
        last_slice = peeked.slice;
    }
    return PeekBackTransliterableResult{
        .slice = @as([*]const u8, @ptrCast(last_slice))[0..total_bytes],
        .codepoint_len = total_codepoint_len,
    };
}

fn matchKana(s: []const u8) ?[]const u8 {
    return trans.transliteration_map.get(s);
}

const MatchBackResult = struct {
    original_slice: []const u8,
    original_codepoint_len: usize,
    matched_slice: []const u8,
};

/// Tries to match the biggest transliterable slice against the last n characters in the input buffer.
///
/// Example (n = 2)
/// - kya -> .{ "ya", "2", "や" }
/// - んi -> .{ "i", "1", "い" }
fn matchBack(self: *Self, n: usize) ?MatchBackResult {
    if (peekBackTransliterable(self, n)) |result| {
        if (result.codepoint_len == 0) {
            return null;
        }
        if (matchKana(result.slice)) |match| {
            return .{
                .original_slice = result.slice,
                .original_codepoint_len = result.codepoint_len,
                .matched_slice = match,
            };
        }
    }
    return null;
}

/// Returns true if the first two codepoints in the slice are the same.
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

    for ("kya") |c| {
        try ime.insert(&.{c});
        std.debug.print("{s}\n", .{ime.input.buf.items});
    }
}

test "transliteration test" {
    const file = @embedFile("./test-data/transliterations.txt");

    var last_comment: ?[]const u8 = null;
    var lines = std.mem.split(u8, file, "\n");

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        if (std.mem.startsWith(u8, trimmed, "#")) {
            last_comment = trimmed;
            std.debug.print("\n{s}\n", .{trimmed});
            continue;
        }

        var parts = std.mem.split(u8, trimmed, " ");
        const romaji = parts.next() orelse continue;
        const hiragana = parts.next() orelse continue;

        // Create a FSM instance for testing
        var ime = Self.init(std.testing.allocator);
        defer ime.deinit();

        // Process each character of the romaji input
        for (romaji) |c| {
            try ime.insert(&.{c});
        }

        std.debug.print("Testing romaji: {s} -> hiragana: {s}\n", .{ romaji, hiragana });

        // Verify output
        try std.testing.expectEqualStrings(hiragana, ime.input.buf.items);
    }
}
