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
    const full_width = matchFullWidth(s) orelse return;
    try self.input.insert(full_width);
    const result = self.peekBackTransliterable(4) orelse return;
    var it = utf8.createUtf8ShrinkingIterator(result.slice);
    while (it.next()) |segment| {
        var mutable_segment = segment;
        const isRepeatCase =
            segment.codepoint_len == 2 and
            !try firstCodepointEqual(&mutable_segment.it, "ｎ") and
            try areFirstTwoCodepointsSame(&mutable_segment.it);
        const isNCase =
            segment.codepoint_len == 2 and
            try firstCodepointEqual(&mutable_segment.it, "ｎ");

        if (isRepeatCase) {
            if (try self.transliterateRepeat(&mutable_segment)) break;
        } else if (isNCase) {
            if (try self.transliterateN(&mutable_segment)) break;
        } else {
            if (try self.transliterateBasicMatch(&mutable_segment)) break;
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

fn matchFullWidth(s: []const u8) ?[]const u8 {
    return trans.full_width_map.get(s);
}

/// Transliterates a repeat case
///
/// - ｔｔ -> っ
fn transliterateRepeat(self: *Self, segment: *utf8.Segment) !bool {
    // might not need match here, since all repeats MIGHT create sokuon
    if (matchKana(segment.it.bytes)) |match| {
        self.input.moveCursorBack(1);
        try self.input.replaceBack(1, match);
        self.input.moveCursorForward(1);
        return true;
    }
    return false;
}

pub const n_fallthrough_cases = std.StaticStringMap(void).initComptime(.{
    // vowels
    .{"ｎａ"}, .{"ｎｉ"}, .{"ｎｕ"}, .{"ｎｅ"}, .{"ｎｏ"}, .{"ｎｎ"},
});

fn isNFallthroughCase(s: []const u8) bool {
    return n_fallthrough_cases.get(s) != null;
}

fn isNYCase(s: []const u8) bool {
    return std.mem.eql(u8, s, "ｎｙ");
}

/// Transliterates an n case
///
/// - ｎａ -> な
/// - ｎｎ -> ん
fn transliterateN(self: *Self, segment: *utf8.Segment) !bool {
    if (isNYCase(segment.it.bytes)) {
        // Do nothing for 'ｎｙ'
        return false;
    }
    if (isNFallthroughCase(segment.it.bytes)) {
        if (matchKana(segment.it.bytes)) |match| {
            try self.input.replaceBack(2, match);
            return true;
        }
        unreachable;
    }
    self.input.moveCursorBack(1);
    try self.input.replaceBack(1, "ん");
    self.input.moveCursorForward(1);
    return true;
}

/// Transliterates basic matches
///
/// - ｋｕ -> く
/// - ｋｙｏ -> きょ
/// - ａ -> あ
fn transliterateBasicMatch(self: *Self, segment: *utf8.Segment) !bool {
    if (matchKana(segment.it.bytes)) |match| {
        try self.input.replaceBack(segment.codepoint_len, match);
        return true;
    }
    return false;
}

/// Returns true if the first codepoint in the iterator is the same as the slice.
fn firstCodepointEqual(it: *unicode.Utf8Iterator, slice: []const u8) !bool {
    const first = it.peek(1);
    if (first.len == 0) return error.InvalidInput;
    return std.mem.eql(u8, first, slice);
}

/// Returns true if the first two codepoints in the iterator are the same.
fn areFirstTwoCodepointsSame(it: *unicode.Utf8Iterator) !bool {
    const first = it.peek(1);
    if (first.len == 0) return error.InvalidInput;
    const first_two = it.peek(2);
    if (first_two.len <= first.len) return error.InvalidInput;
    const second = first_two[first.len..];

    return std.mem.eql(u8, first, second);
}

test "firstCodepointEqual" {
    var it = unicode.Utf8Iterator{ .bytes = "abc", .i = 0 };
    try testing.expect(try firstCodepointEqual(&it, "a"));
    try testing.expect(!try firstCodepointEqual(&it, "b"));

    var it2 = unicode.Utf8Iterator{ .bytes = "あいう", .i = 0 };
    try testing.expect(try firstCodepointEqual(&it2, "あ"));
    try testing.expect(!try firstCodepointEqual(&it2, "い"));

    var it3 = unicode.Utf8Iterator{ .bytes = "", .i = 0 };
    try testing.expectError(error.InvalidInput, firstCodepointEqual(&it3, "a"));
}

test "areFirstTwoCodepointsSame" {
    var it = unicode.Utf8Iterator{ .bytes = "aa", .i = 0 };
    try testing.expect(try areFirstTwoCodepointsSame(&it));

    var it2 = unicode.Utf8Iterator{ .bytes = "ああ", .i = 0 };
    try testing.expect(try areFirstTwoCodepointsSame(&it2));

    var it3 = unicode.Utf8Iterator{ .bytes = "ab", .i = 0 };
    try testing.expect(!try areFirstTwoCodepointsSame(&it3));

    var it4 = unicode.Utf8Iterator{ .bytes = "a", .i = 0 };
    try testing.expectError(error.InvalidInput, areFirstTwoCodepointsSame(&it4));

    var it5 = unicode.Utf8Iterator{ .bytes = "", .i = 0 };
    try testing.expectError(error.InvalidInput, areFirstTwoCodepointsSame(&it5));
}

test "insertion with moving cursor" {
    var ime = Self.init(std.testing.allocator);
    defer ime.deinit();

    try ime.insert("k");
    try ime.insert("c");
    ime.moveCursorBack();
    try ime.insert("i");
    try std.testing.expectEqualStrings("きｃ", ime.input.buf.items);

    ime.reset();

    try ime.insert("k");
    try ime.insert("y");
    try ime.insert("c");
    ime.moveCursorBack();
    try ime.insert("i");
    try std.testing.expectEqualStrings("きぃｃ", ime.input.buf.items);
}

test "random transliterations" {
    try testFromFile("./test-data/random-transliterations.txt");
}

test "all valid kana transliterations" {
    try testFromFile("./test-data/kana-transliterations.txt");
}

test "full width transliterations" {
    try testFromFile("./test-data/full-width-transliterations.txt");
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
