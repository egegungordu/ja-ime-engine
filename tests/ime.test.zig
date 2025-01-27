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
    try ime.deleteBack();
    try std.testing.expectEqualStrings("ｃ", ime.input.buf.items);

    ime.clear();

    // Test deleteForward
    _ = try ime.insert("c");
    _ = try ime.insert("k");
    _ = try ime.insert("a");
    try std.testing.expectEqualStrings("ｃか", ime.input.buf.items);
    ime.moveCursorBack(1);
    try ime.deleteForward();
    try std.testing.expectEqualStrings("ｃ", ime.input.buf.items);
    ime.moveCursorBack(1);
    try ime.deleteForward();
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

test "ime: getMatches" {
    var ime = try Ime(TestDictionaryLoader).init(testing.allocator);
    defer ime.deinit();

    const input = "konnnichihasekai";

    var view = std.unicode.Utf8View.initUnchecked(input);
    var it = view.iterator();

    while (it.nextCodepointSlice()) |char| {
        _ = try ime.insert(char);
    }

    try testing.expectEqualSlices(WordEntry, &.{
        .{ .word = "こんにちは", .left_id = 8, .right_id = 8, .cost = 5704 },
        .{ .word = "世界", .left_id = 24, .right_id = 24, .cost = 5186 },
    }, ime.getMatches().?);
}

test "ime: applyMatch" {
    var ime = try Ime(TestDictionaryLoader).init(testing.allocator);
    defer ime.deinit();

    const input = "konnnichihasekai";

    var view = std.unicode.Utf8View.initUnchecked(input);
    var it = view.iterator();

    while (it.nextCodepointSlice()) |char| {
        _ = try ime.insert(char);
    }

    _ = try ime.applyMatch();

    try testing.expectEqualStrings("こんにちは世界", ime.input.buf.items);
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

        const costs = std.ArrayList(i16).init(allocator);

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

pub const TestDictionaryLoader = struct {
    pub fn loadDictionary(allocator: mem.Allocator) !Dictionary {
        var bldr = LoudsTrieBuilder(WordEntry).init(allocator);
        defer bldr.deinit();

        const entries = [_]struct { []const u8, WordEntry }{
            .{ "か", .{ .word = "香", .left_id = 24, .right_id = 24, .cost = 7981 } },
            .{ "こ", .{ .word = "児", .left_id = 24, .right_id = 24, .cost = 7220 } },
            .{ "こ", .{ .word = "古", .left_id = 14, .right_id = 14, .cost = 7705 } },
            .{ "にちは", .{ .word = "ニチハ", .left_id = 18, .right_id = 18, .cost = 5124 } },
            .{ "はせ", .{ .word = "羽瀬", .left_id = 16, .right_id = 16, .cost = 7727 } },
            .{ "せ", .{ .word = "糶", .left_id = 30, .right_id = 30, .cost = 7542 } },
            .{ "ち", .{ .word = "千", .left_id = 6, .right_id = 6, .cost = 10274 } },
            .{ "はせ", .{ .word = "馳せ", .left_id = 7, .right_id = 7, .cost = 7257 } },
            .{ "せ", .{ .word = "背", .left_id = 24, .right_id = 24, .cost = 6163 } },
            .{ "か", .{ .word = "加", .left_id = 6, .right_id = 6, .cost = 9414 } },
            .{ "か", .{ .word = "下", .left_id = 34, .right_id = 34, .cost = 8675 } },
            .{ "こん", .{ .word = "コン", .left_id = 24, .right_id = 24, .cost = 5818 } },
            .{ "かい", .{ .word = "貝", .left_id = 24, .right_id = 24, .cost = 6418 } },
            .{ "かい", .{ .word = "櫂", .left_id = 24, .right_id = 24, .cost = 6403 } },
            .{ "か", .{ .word = "狩", .left_id = 30, .right_id = 30, .cost = 7612 } },
            .{ "こん", .{ .word = "婚", .left_id = 24, .right_id = 24, .cost = 6869 } },
            .{ "かい", .{ .word = "開", .left_id = 11, .right_id = 11, .cost = 9968 } },
            .{ "せか", .{ .word = "せか", .left_id = 4, .right_id = 4, .cost = 9293 } },
            .{ "は", .{ .word = "端", .left_id = 24, .right_id = 24, .cost = 8596 } },
            .{ "かい", .{ .word = "書い", .left_id = 15, .right_id = 15, .cost = 7883 } },
            .{ "ん", .{ .word = "ン", .left_id = 5, .right_id = 5, .cost = 5812 } },
            .{ "こ", .{ .word = "子", .left_id = 34, .right_id = 34, .cost = 11717 } },
            .{ "い", .{ .word = "良", .left_id = 12, .right_id = 12, .cost = 6468 } },
            .{ "こん", .{ .word = "懇", .left_id = 34, .right_id = 34, .cost = 9003 } },
            .{ "か", .{ .word = "苅", .left_id = 30, .right_id = 30, .cost = 7539 } },
            .{ "こ", .{ .word = "娘", .left_id = 24, .right_id = 24, .cost = 8402 } },
            .{ "はせ", .{ .word = "長谷", .left_id = 6, .right_id = 6, .cost = 9189 } },
            .{ "こん", .{ .word = "金", .left_id = 16, .right_id = 16, .cost = 13199 } },
            .{ "こん", .{ .word = "近", .left_id = 21, .right_id = 21, .cost = 9722 } },
            .{ "に", .{ .word = "煮", .left_id = 7, .right_id = 7, .cost = 6679 } },
            .{ "か", .{ .word = "借", .left_id = 30, .right_id = 30, .cost = 8286 } },
            .{ "こ", .{ .word = "個", .left_id = 35, .right_id = 35, .cost = 9115 } },
            .{ "こん", .{ .word = "昆", .left_id = 16, .right_id = 16, .cost = 8329 } },
            .{ "ち", .{ .word = "知", .left_id = 24, .right_id = 24, .cost = 7725 } },
            .{ "は", .{ .word = "張", .left_id = 30, .right_id = 30, .cost = 8329 } },
            .{ "かい", .{ .word = "下位", .left_id = 24, .right_id = 24, .cost = 6229 } },
            .{ "かい", .{ .word = "回", .left_id = 35, .right_id = 35, .cost = 7597 } },
            .{ "せかい", .{ .word = "世界", .left_id = 24, .right_id = 24, .cost = 5186 } },
            .{ "かい", .{ .word = "峡", .left_id = 24, .right_id = 24, .cost = 6415 } },
            .{ "こ", .{ .word = "小", .left_id = 13, .right_id = 13, .cost = 10383 } },
            .{ "かい", .{ .word = "交い", .left_id = 17, .right_id = 17, .cost = 8414 } },
            .{ "かい", .{ .word = "嗅い", .left_id = 19, .right_id = 19, .cost = 7931 } },
            .{ "せ", .{ .word = "競", .left_id = 30, .right_id = 30, .cost = 8305 } },
            .{ "い", .{ .word = "威", .left_id = 24, .right_id = 24, .cost = 6798 } },
            .{ "い", .{ .word = "い", .left_id = 7, .right_id = 7, .cost = 9045 } },
            .{ "に", .{ .word = "丹", .left_id = 24, .right_id = 24, .cost = 6300 } },
            .{ "い", .{ .word = "李", .left_id = 16, .right_id = 16, .cost = 10673 } },
            .{ "こ", .{ .word = "庫", .left_id = 34, .right_id = 34, .cost = 9824 } },
            .{ "こん", .{ .word = "痕", .left_id = 34, .right_id = 34, .cost = 8796 } },
            .{ "か", .{ .word = "嫁", .left_id = 28, .right_id = 28, .cost = 7163 } },
            .{ "かい", .{ .word = "快", .left_id = 14, .right_id = 14, .cost = 7321 } },
            .{ "こん", .{ .word = "凝ん", .left_id = 23, .right_id = 23, .cost = 7856 } },
            .{ "かい", .{ .word = "買", .left_id = 34, .right_id = 34, .cost = 9525 } },
            .{ "かい", .{ .word = "Χ", .left_id = 29, .right_id = 29, .cost = 1730 } },
            .{ "かい", .{ .word = "飼い", .left_id = 17, .right_id = 17, .cost = 7938 } },
            .{ "か", .{ .word = "火", .left_id = 24, .right_id = 24, .cost = 7111 } },
            .{ "かい", .{ .word = "掻い", .left_id = 15, .right_id = 15, .cost = 7931 } },
            .{ "こん", .{ .word = "込ん", .left_id = 25, .right_id = 25, .cost = 8037 } },
            .{ "か", .{ .word = "過", .left_id = 14, .right_id = 14, .cost = 6658 } },
            .{ "こんにちは", .{ .word = "こんにちは", .left_id = 8, .right_id = 8, .cost = 5704 } },
            .{ "かい", .{ .word = "描い", .left_id = 15, .right_id = 15, .cost = 9808 } },
            .{ "かい", .{ .word = "界", .left_id = 34, .right_id = 34, .cost = 8996 } },
            .{ "い", .{ .word = "飯", .left_id = 6, .right_id = 6, .cost = 10778 } },
            .{ "い", .{ .word = "伊", .left_id = 1, .right_id = 1, .cost = 7562 } },
            .{ "ち", .{ .word = "値", .left_id = 34, .right_id = 34, .cost = 10082 } },
            .{ "は", .{ .word = "派", .left_id = 34, .right_id = 34, .cost = 9536 } },
            .{ "かい", .{ .word = "佳以", .left_id = 11, .right_id = 11, .cost = 9243 } },
            .{ "い", .{ .word = "居", .left_id = 7, .right_id = 7, .cost = 7840 } },
            .{ "かい", .{ .word = "かい", .left_id = 17, .right_id = 17, .cost = 9819 } },
            .{ "い", .{ .word = "炒", .left_id = 30, .right_id = 30, .cost = 8194 } },
            .{ "こん", .{ .word = "崑", .left_id = 11, .right_id = 11, .cost = 9167 } },
            .{ "い", .{ .word = "意", .left_id = 24, .right_id = 24, .cost = 7840 } },
            .{ "こ", .{ .word = "粉", .left_id = 34, .right_id = 34, .cost = 9571 } },
            .{ "か", .{ .word = "化", .left_id = 33, .right_id = 33, .cost = 6390 } },
            .{ "は", .{ .word = "貼", .left_id = 30, .right_id = 30, .cost = 7818 } },
            .{ "かい", .{ .word = "家", .left_id = 34, .right_id = 34, .cost = 8144 } },
            .{ "かい", .{ .word = "海", .left_id = 26, .right_id = 26, .cost = 13848 } },
            .{ "か", .{ .word = "可", .left_id = 34, .right_id = 34, .cost = 9115 } },
            .{ "に", .{ .word = "２", .left_id = 27, .right_id = 27, .cost = 4506 } },
            .{ "かい", .{ .word = "買い", .left_id = 17, .right_id = 17, .cost = 5698 } },
            .{ "い", .{ .word = "煎", .left_id = 30, .right_id = 30, .cost = 8193 } },
            .{ "ん", .{ .word = "ん", .left_id = 3, .right_id = 3, .cost = 13247 } },
            .{ "い", .{ .word = "入", .left_id = 30, .right_id = 30, .cost = 9749 } },
            .{ "ち", .{ .word = "地", .left_id = 34, .right_id = 34, .cost = 9183 } },
            .{ "かい", .{ .word = "χ", .left_id = 29, .right_id = 29, .cost = 1730 } },
            .{ "はせ", .{ .word = "初瀬", .left_id = 6, .right_id = 6, .cost = 8783 } },
            .{ "せ", .{ .word = "妹", .left_id = 6, .right_id = 6, .cost = 9823 } },
            .{ "は", .{ .word = "羽", .left_id = 24, .right_id = 24, .cost = 7024 } },
            .{ "こんにち", .{ .word = "今日", .left_id = 31, .right_id = 31, .cost = 5290 } },
            .{ "い", .{ .word = "鋳", .left_id = 7, .right_id = 7, .cost = 8199 } },
            .{ "に", .{ .word = "尼", .left_id = 11, .right_id = 11, .cost = 8636 } },
            .{ "こ", .{ .word = "弧", .left_id = 24, .right_id = 24, .cost = 6583 } },
            .{ "か", .{ .word = "駈", .left_id = 30, .right_id = 30, .cost = 7539 } },
            .{ "い", .{ .word = "位", .left_id = 34, .right_id = 34, .cost = 8893 } },
            .{ "ち", .{ .word = "散", .left_id = 30, .right_id = 30, .cost = 7821 } },
            .{ "かい", .{ .word = "舁い", .left_id = 15, .right_id = 15, .cost = 7931 } },
            .{ "は", .{ .word = "波", .left_id = 35, .right_id = 35, .cost = 11337 } },
            .{ "かい", .{ .word = "階", .left_id = 34, .right_id = 34, .cost = 7500 } },
            .{ "い", .{ .word = "医", .left_id = 34, .right_id = 34, .cost = 9097 } },
            .{ "ち", .{ .word = "ち", .left_id = 30, .right_id = 30, .cost = 10022 } },
            .{ "か", .{ .word = "価", .left_id = 35, .right_id = 35, .cost = 12336 } },
            .{ "かい", .{ .word = "介", .left_id = 28, .right_id = 28, .cost = 5608 } },
            .{ "こ", .{ .word = "こ", .left_id = 22, .right_id = 22, .cost = 11072 } },
            .{ "ち", .{ .word = "血", .left_id = 24, .right_id = 24, .cost = 6537 } },
            .{ "せ", .{ .word = "畝", .left_id = 24, .right_id = 24, .cost = 6014 } },
            .{ "かい", .{ .word = "怪", .left_id = 24, .right_id = 24, .cost = 6883 } },
            .{ "にち", .{ .word = "日", .left_id = 34, .right_id = 34, .cost = 9386 } },
            .{ "こ", .{ .word = "呼", .left_id = 24, .right_id = 24, .cost = 6602 } },
            .{ "こ", .{ .word = "戸", .left_id = 35, .right_id = 35, .cost = 10391 } },
            .{ "かい", .{ .word = "帆", .left_id = 11, .right_id = 11, .cost = 9243 } },
            .{ "か", .{ .word = "歌", .left_id = 34, .right_id = 34, .cost = 10104 } },
            .{ "かい", .{ .word = "欠い", .left_id = 15, .right_id = 15, .cost = 7873 } },
            .{ "こ", .{ .word = "梱", .left_id = 30, .right_id = 30, .cost = 8111 } },
            .{ "か", .{ .word = "刈", .left_id = 30, .right_id = 30, .cost = 7563 } },
            .{ "こん", .{ .word = "こん", .left_id = 23, .right_id = 23, .cost = 10755 } },
            .{ "こ", .{ .word = "濃", .left_id = 12, .right_id = 12, .cost = 5020 } },
            .{ "か", .{ .word = "駆", .left_id = 30, .right_id = 30, .cost = 7546 } },
            .{ "かい", .{ .word = "支い", .left_id = 17, .right_id = 17, .cost = 8072 } },
            .{ "こん", .{ .word = "梱ん", .left_id = 23, .right_id = 23, .cost = 7855 } },
            .{ "は", .{ .word = "覇", .left_id = 24, .right_id = 24, .cost = 6542 } },
            .{ "い", .{ .word = "衣", .left_id = 24, .right_id = 24, .cost = 7237 } },
            .{ "い", .{ .word = "胃", .left_id = 24, .right_id = 24, .cost = 5240 } },
            .{ "か", .{ .word = "科", .left_id = 34, .right_id = 34, .cost = 8084 } },
            .{ "は", .{ .word = "は", .left_id = 10, .right_id = 10, .cost = 11572 } },
            .{ "こ", .{ .word = "股", .left_id = 24, .right_id = 24, .cost = 5998 } },
            .{ "は", .{ .word = "刃", .left_id = 24, .right_id = 24, .cost = 5451 } },
            .{ "はせ", .{ .word = "派せ", .left_id = 20, .right_id = 20, .cost = 7257 } },
            .{ "こ", .{ .word = "蚕", .left_id = 24, .right_id = 24, .cost = 6584 } },
            .{ "こん", .{ .word = "混ん", .left_id = 25, .right_id = 25, .cost = 7855 } },
            .{ "か", .{ .word = "蚊", .left_id = 24, .right_id = 24, .cost = 6010 } },
            .{ "い", .{ .word = "亥", .left_id = 6, .right_id = 6, .cost = 9720 } },
            .{ "かい", .{ .word = "甲斐", .left_id = 6, .right_id = 6, .cost = 9302 } },
            .{ "はせ", .{ .word = "はせ", .left_id = 7, .right_id = 7, .cost = 9795 } },
            .{ "かい", .{ .word = "会", .left_id = 34, .right_id = 34, .cost = 7354 } },
            .{ "せか", .{ .word = "急か", .left_id = 4, .right_id = 4, .cost = 8020 } },
            .{ "か", .{ .word = "禍", .left_id = 34, .right_id = 34, .cost = 8011 } },
            .{ "かい", .{ .word = "カイ", .left_id = 24, .right_id = 24, .cost = 4874 } },
            .{ "せ", .{ .word = "瀬", .left_id = 24, .right_id = 24, .cost = 6598 } },
            .{ "こん", .{ .word = "樵ん", .left_id = 23, .right_id = 23, .cost = 7855 } },
            .{ "に", .{ .word = "二", .left_id = 27, .right_id = 27, .cost = 2914 } },
            .{ "こ", .{ .word = "湖", .left_id = 35, .right_id = 35, .cost = 11274 } },
            .{ "せか", .{ .word = "堰か", .left_id = 4, .right_id = 4, .cost = 7151 } },
            .{ "か", .{ .word = "課", .left_id = 35, .right_id = 35, .cost = 9075 } },
            .{ "せ", .{ .word = "せ", .left_id = 9, .right_id = 9, .cost = 8659 } },
            .{ "い", .{ .word = "異", .left_id = 14, .right_id = 14, .cost = 7074 } },
            .{ "せか", .{ .word = "塞か", .left_id = 4, .right_id = 4, .cost = 7151 } },
            .{ "こ", .{ .word = "孤", .left_id = 24, .right_id = 24, .cost = 6942 } },
            .{ "かい", .{ .word = "皆", .left_id = 14, .right_id = 14, .cost = 7971 } },
            .{ "こ", .{ .word = "樵", .left_id = 30, .right_id = 30, .cost = 8111 } },
            .{ "に", .{ .word = "荷", .left_id = 24, .right_id = 24, .cost = 6567 } },
            .{ "こ", .{ .word = "凝", .left_id = 30, .right_id = 30, .cost = 8111 } },
            .{ "ち", .{ .word = "治", .left_id = 28, .right_id = 28, .cost = 7357 } },
            .{ "かい", .{ .word = "歌意", .left_id = 24, .right_id = 24, .cost = 6403 } },
            .{ "かい", .{ .word = "加衣", .left_id = 11, .right_id = 11, .cost = 9243 } },
            .{ "せか", .{ .word = "咳か", .left_id = 4, .right_id = 4, .cost = 7151 } },
            .{ "い", .{ .word = "藺", .left_id = 24, .right_id = 24, .cost = 6665 } },
            .{ "こん", .{ .word = "紺", .left_id = 16, .right_id = 16, .cost = 8404 } },
            .{ "かい", .{ .word = "下意", .left_id = 24, .right_id = 24, .cost = 6398 } },
            .{ "い", .{ .word = "射", .left_id = 7, .right_id = 7, .cost = 8209 } },
            .{ "い", .{ .word = "熬", .left_id = 30, .right_id = 30, .cost = 8193 } },
            .{ "に", .{ .word = "似", .left_id = 7, .right_id = 7, .cost = 7484 } },
            .{ "せ", .{ .word = "セ", .left_id = 18, .right_id = 18, .cost = 7343 } },
            .{ "か", .{ .word = "架", .left_id = 28, .right_id = 28, .cost = 6181 } },
            .{ "か", .{ .word = "穫", .left_id = 30, .right_id = 30, .cost = 7539 } },
            .{ "い", .{ .word = "井", .left_id = 24, .right_id = 24, .cost = 7679 } },
            .{ "こ", .{ .word = "鼓", .left_id = 28, .right_id = 28, .cost = 5435 } },
            .{ "は", .{ .word = "歯", .left_id = 24, .right_id = 24, .cost = 6536 } },
            .{ "い", .{ .word = "委", .left_id = 34, .right_id = 34, .cost = 11714 } },
            .{ "い", .{ .word = "要", .left_id = 30, .right_id = 30, .cost = 8212 } },
            .{ "は", .{ .word = "葉", .left_id = 24, .right_id = 24, .cost = 6617 } },
            .{ "こ", .{ .word = "故", .left_id = 14, .right_id = 14, .cost = 5195 } },
            .{ "に", .{ .word = "に", .left_id = 7, .right_id = 7, .cost = 11880 } },
            .{ "ち", .{ .word = "池", .left_id = 34, .right_id = 34, .cost = 9751 } },
            .{ "かい", .{ .word = "解", .left_id = 28, .right_id = 28, .cost = 6320 } },
            .{ "こ", .{ .word = "来", .left_id = 32, .right_id = 32, .cost = 8177 } },
            .{ "か", .{ .word = "賀", .left_id = 6, .right_id = 6, .cost = 9202 } },
            .{ "か", .{ .word = "か", .left_id = 2, .right_id = 2, .cost = 12742 } },
            .{ "こん", .{ .word = "今", .left_id = 14, .right_id = 14, .cost = 7664 } },
        };

        for (entries) |entry| {
            try bldr.insert(entry[0], entry[1]);
        }

        var ltrie = try bldr.build();
        errdefer ltrie.deinit();

        var costs = std.ArrayList(i16).init(allocator);
        try costs.appendSlice(&.{ 32767, -91, 1026, 1184, 1436, 853, -770, 744, -2063, 358, 1136, -1348, 1334, 2548, 2287, 1177, -899, -386, -1483, 1181, 878, -919, 1113, 461, -573, 1109, 5, 1359, -736, -471, 1332, -826, 1323, 65, -156, 28, -952, -6430, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 1253, 32767, -1706, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 1435, 32767, 32767, -1043, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 77, 32767, 32767, 32767, 1987, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 2324, 32767, 32767, 32767, 32767, 1864, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -310, 32767, 32767, 32767, 32767, 32767, -2267, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -815, 32767, 32767, 32767, 32767, 32767, 32767, -761, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -1671, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -1019, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 67, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 175, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 1997, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -80, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -196, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 287, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 475, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 2299, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 61, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -208, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -284, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -1056, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -341, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 2012, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -1655, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -1121, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -1239, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 527, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -978, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 877, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 200, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 1116, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -226, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 1743, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -310, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 178, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 1472, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -1866, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -82, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 2405, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -283, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 62, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 522, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 979, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 2271, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -2732, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 570, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -3266, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 131, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -419, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 24, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 390, 32767, 32767, 32767, 32767, 32767, 32767, 1237, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 3394, 32767, 32767, 32767, 32767, 32767, -316, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 915, 32767, 32767, 32767, 32767, 143, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 1297, 32767, 32767, 32767, 1529, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -2800, 32767, 32767, 2404, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -3990, 32767, 2104, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, 32767, -572 });

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
