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

        pub const MatchModification = struct {
            deleted_codepoints: usize,
            inserted_text: []const u8,
        };

        /// Inserts a slice into the input buffer, doing transliteration if possible.
        /// Only accepts one valid UTF-8 character at a time.
        pub fn insert(self: *Self, s: []const u8) !?MatchModification {
            const full_width_match = try self.tryFullWidthMatch(s) orelse return null;
            const transliterable = self.peekBackTransliterable(4) orelse return full_width_match;
            var it = utf8.createUtf8ShrinkingIterator(transliterable.slice);
            while (it.next()) |segment| {
                if (try self.tryKanaMatch(segment)) |modification| {
                    return modification;
                }
            }
            return full_width_match;
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

        fn tryFullWidthMatch(self: *Self, s: []const u8) !?MatchModification {
            if (getFullWidthMatch(s)) |match| {
                try self.input.insert(match);
                return .{
                    .deleted_codepoints = 0,
                    .inserted_text = match,
                };
            }
            return null;
        }

        /// Transliterates kana matches
        ///
        /// - ｋｕ -> く
        /// - ｋｙｏ -> きょ
        /// - ａ -> あ
        fn tryKanaMatch(self: *Self, segment: utf8.Segment) !?MatchModification {
            if (getKanaMatch(segment.it.bytes)) |match| {
                try self.input.replaceBack(segment.codepoint_len, match);
                return .{
                    .deleted_codepoints = if (segment.codepoint_len > 1) segment.codepoint_len - 1 else 0,
                    .inserted_text = match,
                };
            }
            return null;
        }
    };
}

fn isTransliterable(s: []const u8) bool {
    return trans.transliterables.get(s) != null;
}

fn getKanaMatch(s: []const u8) ?[]const u8 {
    return trans.transliteration_map.get(s);
}

fn getFullWidthMatch(s: []const u8) ?[]const u8 {
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

    // Test basic transliteration (ka -> か)
    if (try ime.insert("k")) |modification| {
        try std.testing.expectEqual(@as(usize, 0), modification.deleted_codepoints);
        try std.testing.expectEqualStrings("ｋ", modification.inserted_text);
    } else {
        try std.testing.expect(false);
    }

    if (try ime.insert("a")) |modification| {
        try std.testing.expectEqual(@as(usize, 1), modification.deleted_codepoints);
        try std.testing.expectEqualStrings("か", modification.inserted_text);
    } else {
        try std.testing.expect(false);
    }
}

test "ime: owned - insert result complex" {
    var ime = Ime(.owned).init(std.testing.allocator);
    defer ime.deinit();

    // Test double consonant (tt -> っｔ)
    if (try ime.insert("t")) |modification| {
        try std.testing.expectEqual(@as(usize, 0), modification.deleted_codepoints);
        try std.testing.expectEqualStrings("ｔ", modification.inserted_text);
    } else {
        try std.testing.expect(false);
    }

    if (try ime.insert("t")) |modification| {
        try std.testing.expectEqual(@as(usize, 1), modification.deleted_codepoints);
        try std.testing.expectEqualStrings("っｔ", modification.inserted_text);
    } else {
        try std.testing.expect(false);
    }

    ime.clear();

    // Case 2: nn -> ん
    if (try ime.insert("n")) |modification| {
        try std.testing.expectEqual(@as(usize, 0), modification.deleted_codepoints);
        try std.testing.expectEqualStrings("ｎ", modification.inserted_text);
    } else {
        try std.testing.expect(false);
    }

    if (try ime.insert("n")) |modification| {
        try std.testing.expectEqual(@as(usize, 1), modification.deleted_codepoints);
        try std.testing.expectEqualStrings("ん", modification.inserted_text);
    } else {
        try std.testing.expect(false);
    }

    ime.clear();

    // Test compound kana (kyo -> きょ)
    if (try ime.insert("k")) |modification| {
        try std.testing.expectEqual(@as(usize, 0), modification.deleted_codepoints);
        try std.testing.expectEqualStrings("ｋ", modification.inserted_text);
    } else {
        try std.testing.expect(false);
    }

    if (try ime.insert("y")) |modification| {
        try std.testing.expectEqual(@as(usize, 0), modification.deleted_codepoints);
        try std.testing.expectEqualStrings("ｙ", modification.inserted_text);
    } else {
        try std.testing.expect(false);
    }

    if (try ime.insert("o")) |modification| {
        try std.testing.expectEqual(@as(usize, 2), modification.deleted_codepoints);
        try std.testing.expectEqualStrings("きょ", modification.inserted_text);
    } else {
        try std.testing.expect(false);
    }
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
    if (try ime.insert("a")) |modification| {
        try std.testing.expectEqual(@as(usize, 0), modification.deleted_codepoints);
        try std.testing.expectEqualStrings("あ", modification.inserted_text);
    } else {
        try std.testing.expect(false);
    }
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
