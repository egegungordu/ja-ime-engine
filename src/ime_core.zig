const std = @import("std");
const mem = std.mem;
const unicode = std.unicode;
const utf8_input = @import("Utf8Input.zig");
const utf8 = @import("utf8.zig");
const trans = @import("transliteration.zig");
const LoudsTrie = @import("LoudsTrie.zig").LoudsTrie([]const u8);

pub fn Ime(
    /// Dictionary loader is a type that implements loadTrie and freeTrie functions.
    /// loadTrie takes an allocator and returns a LoudsTrie that contains dictionary entries.
    /// freeTrie takes an allocator and a LoudsTrie pointer and frees the dictionary.
    /// If dict_loader is null, no dictionary will be loaded and dictionary lookups will be disabled.
    dict_loader: anytype,
) type {
    return struct {
        allocator: mem.Allocator,
        input: utf8_input.Utf8Input,
        dict: ?LoudsTrie,

        const Self = @This();

        pub fn init(allocator: mem.Allocator) !Self {
            const dict: ?LoudsTrie = blk: {
                if (@TypeOf(dict_loader) != type) break :blk null;
                break :blk try dict_loader.loadTrie(allocator);
            };

            return Self{
                .allocator = allocator,
                .input = utf8_input.Utf8Input.init(allocator),
                .dict = dict,
            };
        }

        pub fn deinit(self: *Self) void {
            self.input.deinit();
            if (self.dict != null and @TypeOf(dict_loader) == type) {
                dict_loader.freeTrie(&self.dict.?);
            }
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

const testing = std.testing;

const TestingDictionaryLoader = @import("DictionaryLoader.zig").TestingDictionaryLoader;

test "ime: cursor movement" {
    var ime = try Ime(null).init(testing.allocator);
    defer ime.deinit();

    _ = try ime.insert("k");
    _ = try ime.insert("c");
    ime.moveCursorBack(1);
    _ = try ime.insert("i");
    try testing.expectEqualStrings("きｃ", ime.input.buf.items);

    ime.clear();

    _ = try ime.insert("k");
    _ = try ime.insert("y");
    _ = try ime.insert("c");
    ime.moveCursorBack(1);
    _ = try ime.insert("i");
    try testing.expectEqualStrings("きぃｃ", ime.input.buf.items);

    // Test moveCursorForward
    ime.clear();
    _ = try ime.insert("k");
    _ = try ime.insert("y");
    ime.moveCursorBack(2);
    ime.moveCursorForward(1);
    _ = try ime.insert("i");
    try testing.expectEqualStrings("きｙ", ime.input.buf.items);
}

test "ime: deletion" {
    var ime = try Ime(null).init(std.testing.allocator);
    defer ime.deinit();

    // Test deleteBack
    _ = try ime.insert("c");
    _ = try ime.insert("k");
    _ = try ime.insert("a");
    try std.testing.expectEqualStrings("ｃか", ime.input.buf.items);
    ime.deleteBack();
    try std.testing.expectEqualStrings("ｃ", ime.input.buf.items);

    ime.clear();

    // Test deleteForward
    _ = try ime.insert("c");
    _ = try ime.insert("k");
    _ = try ime.insert("a");
    try std.testing.expectEqualStrings("ｃか", ime.input.buf.items);
    ime.moveCursorBack(1);
    ime.deleteForward();
    try std.testing.expectEqualStrings("ｃ", ime.input.buf.items);
    ime.moveCursorBack(1);
    ime.deleteForward();
    try std.testing.expectEqualStrings("", ime.input.buf.items);
}

test "ime: transliteration random" {
    try testFromFile("tests/data/random-transliterations.txt");
}

test "ime: transliteration kana" {
    try testFromFile("tests/data/kana-transliterations.txt");
}

test "ime: transliteration full width" {
    try testFromFile("tests/data/full-width-transliterations.txt");
}

test "ime: insert result basic" {
    var ime = try Ime(null).init(std.testing.allocator);
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

test "ime: insert result complex" {
    var ime = try Ime(null).init(std.testing.allocator);
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

fn testFromFile(comptime path: []const u8) !void {
    const file = @embedFile(path);

    var lines = std.mem.split(u8, file, "\n");

    var ime = try Ime(null).init(std.testing.allocator);
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
        try std.testing.expectEqualStrings(hiragana, ime.input.buf.items);

        ime.clear();
    }
}
