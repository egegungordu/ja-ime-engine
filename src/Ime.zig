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
/// Only accepts one valid UTF-8 character at a time.
pub fn insert(self: *Self, s: []const u8) !void {
    try self.input.insert(s);
    const result = self.peekBackTransliterable(4) orelse return;
    var it = utf8.createUtf8ShrinkingIterator(result.slice);
    while (it.next()) |segment| {
        const isRepeatCase =
            segment.codepoint_len == 2 and
            segment.slice[0] != 'n' and
            areFirstTwoCodepointsSame(segment.slice);
        const isNCase =
            segment.codepoint_len == 2 and
            segment.slice[0] == 'n';

        if (isRepeatCase) {
            if (try self.transliterateRepeat(segment)) break;
        } else if (isNCase) {
            if (try self.transliterateN(segment)) break;
        } else {
            if (try self.transliterateBasicMatch(segment)) break;
        }
    }
}

pub fn reset(self: *Self) void {
    self.input.buf.clearRetainingCapacity();
    self.input.cursor = 0;
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
/// - "hello" -> .{ "lo", 2 }
/// - "んg" -> .{ "g", 1 }
fn peekBackTransliterable(self: *Self, n: usize) ?PeekBackTransliterableResult {
    var total_bytes: usize = 0;
    var total_codepoint_len: usize = 0;
    var last_slice: []const u8 = undefined;
    for (0..n) |i| {
        const peeked = self.input.peekBackOne(i);
        if (peeked.codepoint_len == 0 or !isTransliterable(peeked.slice)) {
            if (total_bytes == 0) return null;
            return PeekBackTransliterableResult{
                .slice = @as([*]const u8, @ptrCast(last_slice.ptr))[0..total_bytes],
                .codepoint_len = total_codepoint_len,
            };
        }
        total_codepoint_len += peeked.codepoint_len;
        total_bytes += peeked.slice.len;
        last_slice = peeked.slice;
    }
    if (total_bytes == 0) return null;
    return PeekBackTransliterableResult{
        .slice = @as([*]const u8, @ptrCast(last_slice))[0..total_bytes],
        .codepoint_len = total_codepoint_len,
    };
}

fn matchKana(s: []const u8) ?[]const u8 {
    return trans.transliteration_map.get(s);
}

fn transliterateRepeat(self: *Self, segment: utf8.Segment) !bool {
    // might not need match here, since all repeats MIGHT create sokuon
    if (matchKana(segment.slice)) |match| {
        self.input.moveCursorBack(1);
        try self.input.replaceBack(1, match);
        self.input.moveCursorForward(1);
        return true;
    }
    return false;
}

fn transliterateN(self: *Self, segment: utf8.Segment) !bool {
    switch (segment.slice[1]) {
        'y' => {},
        'a', 'i', 'u', 'e', 'o', 'n' => if (matchKana(segment.slice)) |match| {
            try self.input.replaceBack(2, match);
            return true;
        },
        else => {
            self.input.moveCursorBack(1);
            try self.input.replaceBack(1, "ん");
            self.input.moveCursorForward(1);
            return true;
        },
    }
    return false;
}

fn transliterateBasicMatch(self: *Self, segment: utf8.Segment) !bool {
    if (matchKana(segment.slice)) |match| {
        try self.input.replaceBack(segment.codepoint_len, match);
        return true;
    }
    return false;
}

/// Returns true if the first two codepoints in the slice are the same.
/// Assumes that the slice is a valid UTF-8 sequence.
fn areFirstTwoCodepointsSame(slice: []const u8) bool {
    var view = unicode.Utf8View.initUnchecked(slice);
    var it = view.iterator();

    const first = it.nextCodepoint() orelse return false;
    const second = it.nextCodepoint() orelse return false;

    return first == second;
}

test "ime" {
    var ime = Self.init(std.testing.allocator);
    defer ime.deinit();

    // cekosyalilastiramadiklarimizdanmisiniz
    // せこしゃぃぁｓちらまぢｋぁりみｚだんみしにｚ

    for ("cekosyalilastiramadiklarimizdanmisiniz") |c| {
        try ime.insert(&.{c});
        std.debug.print("{s}\n", .{ime.input.buf.items});
    }
}

test "areFirstTwoCodepointsSame" {
    try testing.expect(areFirstTwoCodepointsSame("aa"));
    try testing.expect(areFirstTwoCodepointsSame("ああ"));
    try testing.expect(!areFirstTwoCodepointsSame("ab"));
    try testing.expect(!areFirstTwoCodepointsSame("a"));
    try testing.expect(!areFirstTwoCodepointsSame(""));
}

test "insertion with moving cursor" {
    var ime = Self.init(std.testing.allocator);
    defer ime.deinit();

    try ime.insert("k");
    try ime.insert("c");
    ime.moveCursorBack();
    try ime.insert("i");
    try std.testing.expectEqualStrings("きc", ime.input.buf.items);

    ime.reset();

    try ime.insert("k");
    try ime.insert("y");
    try ime.insert("c");
    ime.moveCursorBack();
    try ime.insert("i");
    try std.testing.expectEqualStrings("きぃc", ime.input.buf.items);
}

test "random transliterations" {
    try testFromFile("./test-data/random-transliterations.txt");
}

test "all valid transliterations" {
    try testFromFile("./test-data/transliterations.txt");
}

fn testFromFile(comptime path: []const u8) !void {
    const file = @embedFile(path);

    var last_comment: ?[]const u8 = null;
    var lines = std.mem.split(u8, file, "\n");

    var ime = Self.init(std.testing.allocator);
    defer ime.deinit();

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

        // Process each character of the romaji input
        for (romaji) |c| {
            try ime.insert(&.{c});
        }

        std.debug.print("\nTesting romaji: {s} -> hiragana: {s}", .{ romaji, hiragana });

        // Verify output
        try std.testing.expectEqualStrings(hiragana, ime.input.buf.items);

        ime.reset();
    }
}
