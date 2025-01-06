const std = @import("std");
const mem = std.mem;
const unicode = std.unicode;
const testing = @import("std").testing;
const utf8_input = @import("Utf8Input.zig");
const utf8 = @import("utf8.zig");
const trans = @import("transliteration.zig");

pub fn Ime(comptime tag: utf8_input.StorageTag) type {
    return struct {
        input: utf8_input.Utf8Input(tag),

        const Self = @This();

        pub fn init(
            arg: switch (tag) {
                .owned => mem.Allocator,
                .borrowed => []u8,
            },
        ) Self {
            return Self{
                .input = utf8_input.Utf8Input(tag).init(arg),
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

        pub fn clear(self: *Self) void {
            self.input.clear();
        }

        pub fn moveCursorForward(self: *Self) void {
            self.input.moveCursorForward(1);
        }

        pub fn moveCursorBack(self: *Self) void {
            self.input.moveCursorBack(1);
        }

        pub fn deleteBack(self: *Self) void {
            self.input.deleteBack(1);
        }

        pub fn deleteForward(self: *Self) void {
            self.input.deleteForward(1);
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
    };
}

fn isTransliterable(s: []const u8) bool {
    return trans.transliterables.get(s) != null;
}

fn matchKana(s: []const u8) ?[]const u8 {
    return trans.transliteration_map.get(s);
}

fn matchFullWidth(s: []const u8) ?[]const u8 {
    return trans.full_width_map.get(s);
}

const n_fallthrough_cases = std.StaticStringMap(void).initComptime(.{
    // vowels
    .{"ｎａ"}, .{"ｎｉ"}, .{"ｎｕ"}, .{"ｎｅ"}, .{"ｎｏ"}, .{"ｎｎ"},
});

fn isNFallthroughCase(s: []const u8) bool {
    return n_fallthrough_cases.get(s) != null;
}

fn isNYCase(s: []const u8) bool {
    return std.mem.eql(u8, s, "ｎｙ");
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

// Utility tests
test "ime: utils - first codepoint comparison" {
    var it = unicode.Utf8Iterator{ .bytes = "abc", .i = 0 };
    try testing.expect(try firstCodepointEqual(&it, "a"));
    try testing.expect(!try firstCodepointEqual(&it, "b"));

    var it2 = unicode.Utf8Iterator{ .bytes = "あいう", .i = 0 };
    try testing.expect(try firstCodepointEqual(&it2, "あ"));
    try testing.expect(!try firstCodepointEqual(&it2, "い"));

    var it3 = unicode.Utf8Iterator{ .bytes = "", .i = 0 };
    try testing.expectError(error.InvalidInput, firstCodepointEqual(&it3, "a"));
}

test "ime: utils - codepoint equality" {
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

// Owned buffer tests
test "ime: owned - cursor movement" {
    var ime = Ime(.owned).init(std.testing.allocator);
    defer ime.deinit();

    try ime.insert("k");
    try ime.insert("c");
    ime.moveCursorBack();
    try ime.insert("i");
    try std.testing.expectEqualStrings("きｃ", ime.input.buf.items());

    ime.clear();

    try ime.insert("k");
    try ime.insert("y");
    try ime.insert("c");
    ime.moveCursorBack();
    try ime.insert("i");
    try std.testing.expectEqualStrings("きぃｃ", ime.input.buf.items());
}

test "ime: owned - deletion" {
    var ime = Ime(.owned).init(std.testing.allocator);
    defer ime.deinit();

    // Test deleteBack
    try ime.insert("c");
    try ime.insert("k");
    try ime.insert("a");
    try std.testing.expectEqualStrings("ｃか", ime.input.buf.items());
    ime.deleteBack();
    try std.testing.expectEqualStrings("ｃ", ime.input.buf.items());

    ime.clear();

    // Test deleteForward
    try ime.insert("c");
    try ime.insert("k");
    try ime.insert("a");
    try std.testing.expectEqualStrings("ｃか", ime.input.buf.items());
    ime.moveCursorBack();
    ime.deleteForward();
    try std.testing.expectEqualStrings("ｃ", ime.input.buf.items());
    ime.moveCursorBack();
    ime.deleteForward();
    try std.testing.expectEqualStrings("", ime.input.buf.items());
}

test "ime: owned - transliteration random" {
    try testFromFile(.owned, "./test-data/random-transliterations.txt");
}

test "ime: owned - transliteration kana" {
    try testFromFile(.owned, "./test-data/kana-transliterations.txt");
}

test "ime: owned - transliteration full width" {
    try testFromFile(.owned, "./test-data/full-width-transliterations.txt");
}

// Borrowed buffer tests
test "ime: borrowed - cursor movement" {
    var buf: [100]u8 = undefined;
    var ime = Ime(.borrowed).init(&buf);
    defer ime.deinit();

    try ime.insert("k");
    try ime.insert("c");
    ime.moveCursorBack();
    try ime.insert("i");
    try std.testing.expectEqualStrings("きｃ", ime.input.buf.items());

    ime.clear();

    try ime.insert("k");
    try ime.insert("y");
    try ime.insert("c");
    ime.moveCursorBack();
    try ime.insert("i");
    try std.testing.expectEqualStrings("きぃｃ", ime.input.buf.items());
}

test "ime: borrowed - deletion" {
    var buf: [100]u8 = undefined;
    var ime = Ime(.borrowed).init(&buf);
    defer ime.deinit();

    // Test deleteBack
    try ime.insert("c");
    try ime.insert("k");
    try ime.insert("a");
    try std.testing.expectEqualStrings("ｃか", ime.input.buf.items());
    ime.deleteBack();
    try std.testing.expectEqualStrings("ｃ", ime.input.buf.items());
    ime.deleteBack();
    try std.testing.expectEqualStrings("", ime.input.buf.items());

    ime.clear();

    // Test deleteForward
    try ime.insert("c");
    try ime.insert("k");
    try ime.insert("a");
    try std.testing.expectEqualStrings("ｃか", ime.input.buf.items());
    ime.moveCursorBack();
    ime.deleteForward();
    try std.testing.expectEqualStrings("ｃ", ime.input.buf.items());
    ime.moveCursorBack();
    ime.deleteForward();
    try std.testing.expectEqualStrings("", ime.input.buf.items());
}

test "ime: borrowed - transliteration random" {
    try testFromFile(.borrowed, "./test-data/random-transliterations.txt");
}

test "ime: borrowed - transliteration kana" {
    try testFromFile(.borrowed, "./test-data/kana-transliterations.txt");
}

test "ime: borrowed - transliteration full width" {
    try testFromFile(.borrowed, "./test-data/full-width-transliterations.txt");
}

test "ime: borrowed - buffer overflow" {
    // Buffer only big enough for 3 characters
    var buf: [3]u8 = undefined;
    var ime = Ime(.borrowed).init(&buf);
    defer ime.deinit();

    // Single character works
    try ime.insert("a");
    try testing.expectEqualStrings("あ", ime.input.buf.items());

    // Second character fails because 'あ' takes 3 bytes
    try testing.expectError(error.OutOfMemory, ime.insert("a"));
}

fn testFromFile(comptime tag: utf8_input.StorageTag, comptime path: []const u8) !void {
    const file = @embedFile(path);

    var lines = std.mem.split(u8, file, "\n");

    var buf: [1024]u8 = undefined;
    var ime = switch (tag) {
        .owned => Ime(.owned).init(std.testing.allocator),
        .borrowed => Ime(.borrowed).init(&buf),
    };
    defer ime.deinit();

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        if (std.mem.startsWith(u8, trimmed, "#")) {
            continue;
        }

        var parts = std.mem.split(u8, trimmed, " ");
        const romaji = parts.next() orelse continue;
        const hiragana = parts.next() orelse continue;

        // Process each character of the romaji input
        for (romaji) |c| {
            try ime.insert(&.{c});
        }

        // Verify output
        try std.testing.expectEqualStrings(hiragana, ime.input.buf.items());

        ime.clear();
    }
}
