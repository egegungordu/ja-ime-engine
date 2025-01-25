const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const core = @import("core");
const datastructs = @import("datastructs");
const Ime = core.ime.Ime;
const WordEntry = core.WordEntry;
const Dictionary = core.dictionary.Dictionary;
const LoudsTrieBuilder = datastructs.louds_trie.LoudsTrieBuilder;
const LoudsTrie = datastructs.louds_trie.LoudsTrie;

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
    try testFromFile("data/random-transliterations.txt");
}

test "ime: transliteration kana" {
    try testFromFile("data/kana-transliterations.txt");
}

test "ime: transliteration full width" {
    try testFromFile("data/full-width-transliterations.txt");
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

test "ime: exact match" {
    var ime = try Ime(TestingDictionaryLoader).init(testing.allocator);
    defer ime.deinit();

    inline for ([_]struct { r: []const u8, w: []const WordEntry }{
        .{
            .r = "ひらめく",
            .w = &.{
                .{ .word = "閃く" },
            },
        },
        .{
            .r = "こうがく",
            .w = &.{
                .{ .word = "工学" },
                .{ .word = "光学" },
                .{ .word = "高額" },
            },
        },
    }) |pair| {
        try testing.expectEqualSlices(
            WordEntry,
            pair.w,
            (try ime.dict.?.trie.exactMatch(pair.r)).?.values,
        );
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

pub const TestingDictionaryLoader = struct {
    pub fn loadDictionary(allocator: mem.Allocator) !Dictionary {
        var bldr = LoudsTrieBuilder(WordEntry).init(allocator);
        defer bldr.deinit();

        const entries = [_]struct { []const u8, WordEntry }{
            .{ "ひらめく", .{ .word = "閃く" } },
            .{ "ひらく", .{ .word = "開く" } },
            .{ "ひらける", .{ .word = "開ける" } },
            .{ "たべる", .{ .word = "食べる" } },
            .{ "たべつづける", .{ .word = "食べ続ける" } },
            .{ "たべすぎる", .{ .word = "食べ過ぎる" } },
            .{ "こうがく", .{ .word = "工学" } },
            .{ "こうがく", .{ .word = "光学" } },
            .{ "こうがく", .{ .word = "高額" } },
        };

        for (entries) |entry| {
            try bldr.insert(entry[0], entry[1]);
        }

        var ltrie = try bldr.build();
        errdefer ltrie.deinit();

        const costs = std.ArrayList(isize).init(allocator);

        return .{
            .trie = ltrie,
            .costs = costs,
            .right_count = 0,
        };
    }

    pub fn freeDictionary(dict: *Dictionary) void {
        dict.deinit();
    }
};
