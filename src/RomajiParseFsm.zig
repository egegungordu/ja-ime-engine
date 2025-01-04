const std = @import("std");
const mem = std.mem;
const hiragana_map = @import("hiragana.zig").TransliterationMap;
const small_hiragana_map = @import("hiragana.zig").SmallTransliterationMap;
const CharacterSets = @import("CharacterSets.zig");

allocator: mem.Allocator,
current_state: State,
current_small_state: bool,
input: std.ArrayList(u8),
output: std.ArrayList(u8),

const Self = @This();

pub const State = union(enum) {
    Start,
    SingleConsonant: u8,
    LongConsonant: struct { u8, u8 },
    NConsonant,
};

pub const Result = struct { input: []const u8, output: []const u8 };

pub fn init(allocator: mem.Allocator) !Self {
    return .{
        .allocator = allocator,
        .current_state = .Start,
        .current_small_state = false,
        .input = std.ArrayList(u8).init(allocator),
        .output = std.ArrayList(u8).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.input.deinit();
    self.output.deinit();
}

fn isVowel(char: u8) bool {
    return CharacterSets.vowels.isSet(char);
}

fn isConsonant(char: u8) bool {
    return CharacterSets.consonants.isSet(char);
}

fn isSmallMarker(char: u8) bool {
    return CharacterSets.small_markers.isSet(char);
}

pub fn process(self: *Self, input: u8) !Result {
    try self.input.append(input);

    switch (self.current_state) {
        .Start => try self.handleStartState(input),
        .SingleConsonant => |consonant| try self.handleSingleConsonantState(consonant, input),
        .NConsonant => try self.handleNConsonantState(input),
        .LongConsonant => |consonants| try self.handleLongConsonantState(consonants, input),
    }

    return .{ .input = self.input.items, .output = self.output.items };
}

fn handleStartState(self: *Self, input: u8) !void {
    if (isConsonant(input)) {
        self.current_state = .{ .SingleConsonant = input };
        try self.appendChar(input);
    } else if (input == 'n') {
        try self.appendChar('n');
        self.current_state = .NConsonant;
    } else if (isVowel(input)) {
        _ = try self.appendKana(&[1]u8{input}, 0);
        self.resetState();
    } else if (isSmallMarker(input)) {
        try self.appendChar(input);
        self.current_small_state = true;
    }
}

fn handleSingleConsonantState(self: *Self, consonant: u8, input: u8) !void {
    if (isVowel(input)) {
        _ = try self.appendKana(&[2]u8{ consonant, input }, 1);
        self.resetState();
    } else if (input == 'n') {
        try self.appendChar('n');
        self.current_state = .NConsonant;
    } else if (isConsonant(input)) {
        if (input == consonant) {
            self.removeLast(1);
            try self.output.appendSlice("っ");
            self.current_state = .{ .SingleConsonant = input };
        } else {
            self.current_state = .{ .LongConsonant = .{ consonant, input } };
        }
        try self.appendChar(input);
    } else if (isSmallMarker(input)) {
        try self.appendChar(input);
        self.current_small_state = true;
        self.current_state = .Start;
    } else {
        self.resetState();
    }
}

fn handleNConsonantState(self: *Self, input: u8) !void {
    if (isVowel(input)) {
        _ = try self.appendKana(&[2]u8{ 'n', input }, 1);
        self.resetState();
    } else if (input == 'y') {
        try self.appendChar('y');
        self.current_state = .{ .LongConsonant = .{ 'n', 'y' } };
    } else if (isConsonant(input)) {
        _ = try self.appendKana(&[1]u8{'n'}, 1);
        try self.appendChar(input);
        self.current_state = .{ .SingleConsonant = input };
    } else if (input == 'n') {
        _ = try self.appendKana(&[1]u8{'n'}, 1);
        self.resetState();
    } else if (isSmallMarker(input)) {
        try self.appendChar(input);
        self.current_small_state = true;
        self.current_state = .Start;
    } else {
        self.resetState();
    }
}

fn handleLongConsonantState(self: *Self, consonants: struct { u8, u8 }, input: u8) !void {
    const c1 = consonants[0];
    const c2 = consonants[1];
    if (try self.appendKana(&[3]u8{ c1, c2, input }, 2)) {
        self.resetState();
    } else {
        try self.handleSingleConsonantState(c2, input);
    }
}

fn resetState(self: *Self) void {
    self.current_state = .Start;
    self.current_small_state = false;
}

fn getHiragana(self: *Self, key: []const u8) ?[]const u8 {
    if (self.current_small_state and small_hiragana_map.has(key)) {
        self.removeLast(1);
        return small_hiragana_map.get(key);
    }
    return hiragana_map.get(key);
}

fn appendKana(self: *Self, romaji: []const u8, remove_last_n: usize) !bool {
    if (self.getHiragana(romaji)) |kana| {
        self.removeLast(remove_last_n);
        try self.output.appendSlice(kana);
        return true;
    }
    return false;
}

fn appendChar(self: *Self, char: u8) !void {
    try self.output.append(char);
}

fn removeLast(self: *Self, len: usize) void {
    for (0..len) |_| {
        _ = self.output.pop();
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
        var fsm = try Self.init(std.testing.allocator);
        defer fsm.deinit();

        // Process each character of the romaji input
        for (romaji) |c| {
            _ = try fsm.process(c);
        }

        std.debug.print("Testing romaji: {s} -> hiragana: {s}\n", .{ romaji, hiragana });

        // Verify both input collection and output conversion
        try std.testing.expectEqualStrings(romaji, fsm.input.items);
        try std.testing.expectEqualStrings(hiragana, fsm.output.items);
    }
}
