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

        pub const InsertResult = struct {
            // Number of codepoints deleted during the operation
            deleted_codepoints: usize,

            // The direction of deletion (can be forward or backward)
            deletion_direction: ?enum { forward, backward },

            // The actual characters that were inserted (as a slice)
            inserted_text: []const u8,
        };

        /// Inserts a slice into the input buffer, doing transliteration if possible.
        /// Only accepts one valid UTF-8 character at a time.
        pub fn insert(self: *Self, s: []const u8) !InsertResult {
            var result = InsertResult{
                .deleted_codepoints = 0,
                .deletion_direction = null,
                .inserted_text = "",
            };

            const full_width = matchFullWidth(s) orelse return result;
            try self.input.insert(full_width);
            result.inserted_text = full_width;

            const transliterable = self.peekBackTransliterable(4) orelse return result;
            var it = utf8.createUtf8ShrinkingIterator(transliterable.slice);
            while (it.next()) |segment| {
                if (try self.transliterateMatch(segment, &result)) break;
            }
            return result;
        }

        pub fn clear(self: *Self) void {
            self.input.clear();
        }

        pub fn moveCursorForward(self: *Self, n: usize) void {
            self.input.moveCursorForward(n);
        }

        pub fn moveCursorBack(self: *Self, n: usize) void {
            self.input.moveCursorBack(n);
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

        /// Transliterates matches
        ///
        /// - ｋｕ -> く
        /// - ｋｙｏ -> きょ
        /// - ａ -> あ
        fn transliterateMatch(self: *Self, segment: utf8.Segment, result: *InsertResult) !bool {
            if (matchKana(segment.it.bytes)) |match| {
                try self.input.replaceBack(segment.codepoint_len, match);
                if (segment.codepoint_len > 1) {
                    result.deletion_direction = .backward;
                    result.deleted_codepoints = segment.codepoint_len - 1;
                }
                result.inserted_text = match;
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

// Owned buffer tests
test "ime: owned - cursor movement" {
    var ime = Ime(.owned).init(std.testing.allocator);
    defer ime.deinit();

    _ = try ime.insert("k");
    _ = try ime.insert("c");
    ime.moveCursorBack(1);
    _ = try ime.insert("i");
    try std.testing.expectEqualStrings("きｃ", ime.input.buf.items());

    ime.clear();

    _ = try ime.insert("k");
    _ = try ime.insert("y");
    _ = try ime.insert("c");
    ime.moveCursorBack(1);
    _ = try ime.insert("i");
    try std.testing.expectEqualStrings("きぃｃ", ime.input.buf.items());

    // Test moveCursorForward
    ime.clear();
    _ = try ime.insert("k");
    _ = try ime.insert("y");
    ime.moveCursorBack(2);
    ime.moveCursorForward(1);
    _ = try ime.insert("i");
    try std.testing.expectEqualStrings("きｙ", ime.input.buf.items());
}

test "ime: owned - deletion" {
    var ime = Ime(.owned).init(std.testing.allocator);
    defer ime.deinit();

    // Test deleteBack
    _ = try ime.insert("c");
    _ = try ime.insert("k");
    _ = try ime.insert("a");
    try std.testing.expectEqualStrings("ｃか", ime.input.buf.items());
    ime.deleteBack();
    try std.testing.expectEqualStrings("ｃ", ime.input.buf.items());

    ime.clear();

    // Test deleteForward
    _ = try ime.insert("c");
    _ = try ime.insert("k");
    _ = try ime.insert("a");
    try std.testing.expectEqualStrings("ｃか", ime.input.buf.items());
    ime.moveCursorBack(1);
    ime.deleteForward();
    try std.testing.expectEqualStrings("ｃ", ime.input.buf.items());
    ime.moveCursorBack(1);
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

test "ime: owned - insert result basic" {
    var ime = Ime(.owned).init(std.testing.allocator);
    defer ime.deinit();

    // Test basic transliteration (ａ -> あ)
    var result = try ime.insert("k");
    try std.testing.expectEqual(@as(usize, 0), result.deleted_codepoints);
    try std.testing.expectEqualStrings("ｋ", result.inserted_text);
    try std.testing.expectEqual(result.deletion_direction, null);

    // Test no modification case
    result = try ime.insert("a");
    try std.testing.expectEqual(@as(usize, 1), result.deleted_codepoints);
    try std.testing.expectEqualStrings("か", result.inserted_text);
    try std.testing.expectEqual(result.deletion_direction, .backward);
}

test "ime: owned - insert result complex" {
    var ime = Ime(.owned).init(std.testing.allocator);
    defer ime.deinit();

    // Test double consonant (tt -> っｔ)
    var result = try ime.insert("t");
    try std.testing.expectEqual(@as(usize, 0), result.deleted_codepoints);
    try std.testing.expectEqualStrings("ｔ", result.inserted_text);

    result = try ime.insert("t");
    try std.testing.expectEqual(@as(usize, 1), result.deleted_codepoints);
    try std.testing.expectEqualStrings("っｔ", result.inserted_text);

    ime.clear();

    // Case 2: nn -> ん
    result = try ime.insert("n");
    try std.testing.expectEqual(@as(usize, 0), result.deleted_codepoints);
    try std.testing.expectEqualStrings("ｎ", result.inserted_text);

    result = try ime.insert("n");
    try std.testing.expectEqual(@as(usize, 1), result.deleted_codepoints);
    try std.testing.expectEqualStrings("ん", result.inserted_text);

    ime.clear();

    // Test compound kana (kyo -> きょ)
    result = try ime.insert("k");
    try std.testing.expectEqual(@as(usize, 0), result.deleted_codepoints);
    try std.testing.expectEqualStrings("ｋ", result.inserted_text);

    result = try ime.insert("y");
    try std.testing.expectEqual(@as(usize, 0), result.deleted_codepoints);
    try std.testing.expectEqualStrings("ｙ", result.inserted_text);

    result = try ime.insert("o");
    try std.testing.expectEqual(@as(usize, 2), result.deleted_codepoints);
    try std.testing.expectEqualStrings("きょ", result.inserted_text);
}

// Borrowed buffer tests
test "ime: borrowed - cursor movement" {
    var buf: [100]u8 = undefined;
    var ime = Ime(.borrowed).init(&buf);
    defer ime.deinit();

    _ = try ime.insert("k");
    _ = try ime.insert("c");
    ime.moveCursorBack(1);
    _ = try ime.insert("i");
    try std.testing.expectEqualStrings("きｃ", ime.input.buf.items());

    ime.clear();

    _ = try ime.insert("k");
    _ = try ime.insert("y");
    _ = try ime.insert("c");
    ime.moveCursorBack(1);
    _ = try ime.insert("i");
    try std.testing.expectEqualStrings("きぃｃ", ime.input.buf.items());

    // Test moveCursorForward
    ime.clear();
    _ = try ime.insert("k");
    _ = try ime.insert("y");
    ime.moveCursorBack(2);
    ime.moveCursorForward(1);
    _ = try ime.insert("i");
    try std.testing.expectEqualStrings("きｙ", ime.input.buf.items());
}

test "ime: borrowed - deletion" {
    var buf: [100]u8 = undefined;
    var ime = Ime(.borrowed).init(&buf);
    defer ime.deinit();

    // Test deleteBack
    _ = try ime.insert("c");
    _ = try ime.insert("k");
    _ = try ime.insert("a");
    try std.testing.expectEqualStrings("ｃか", ime.input.buf.items());
    ime.deleteBack();
    try std.testing.expectEqualStrings("ｃ", ime.input.buf.items());
    ime.deleteBack();
    try std.testing.expectEqualStrings("", ime.input.buf.items());

    ime.clear();

    // Test deleteForward
    _ = try ime.insert("c");
    _ = try ime.insert("k");
    _ = try ime.insert("a");
    try std.testing.expectEqualStrings("ｃか", ime.input.buf.items());
    ime.moveCursorBack(1);
    ime.deleteForward();
    try std.testing.expectEqualStrings("ｃ", ime.input.buf.items());
    ime.moveCursorBack(1);
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
    _ = try ime.insert("a");
    try testing.expectEqualStrings("あ", ime.input.buf.items());

    // Second character fails because 'あ' takes 3 bytes
    try testing.expectError(error.OutOfMemory, ime.insert("a"));
}

test "ime: borrowed - insert result" {
    var buf: [100]u8 = undefined;
    var ime = Ime(.borrowed).init(&buf);
    defer ime.deinit();

    // Test basic case
    const result = try ime.insert("a");
    try std.testing.expectEqual(@as(usize, 0), result.deleted_codepoints);
    try std.testing.expectEqualStrings("あ", result.inserted_text);
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
            _ = try ime.insert(&.{c});
        }

        // Verify output
        try std.testing.expectEqualStrings(hiragana, ime.input.buf.items());

        ime.clear();
    }
}
