const std = @import("std");
const mem = std.mem;
const hiragana_map = @import("hiragana.zig").TransliterationMap;
const small_hiragana_map = @import("hiragana.zig").SmallTransliterationMap;

allocator: mem.Allocator,
current_state: State,
current_small_state: bool,
input: std.ArrayList(u8),
output: std.ArrayList(u8),

const Self = @This();

pub const State = union(enum) {
    Start,
    SingleConsonant: u8,
    PalatalizedConsonant: u8,
    NConsonant,
    ChConsonant,
    TsConsonant,
    ThConsonant,
    ShConsonant,
};

pub const Result = struct { input: []const u8, output: []const u8 };

pub fn init(allocator: mem.Allocator) !Self {
    // zig fmt: off
    return .{ 
        .allocator = allocator, 
        .current_state = .Start,
        .current_small_state = false,
        .input = std.ArrayList(u8).init(allocator),
        .output = std.ArrayList(u8).init(allocator),
    };
    // zig fmt: on
}

pub fn deinit(self: *Self) void {
    self.input.deinit();
    self.output.deinit();
}

pub fn process(self: *Self, input: u8) !Result {
    try self.input.append(input);

    switch (self.current_state) {
        .Start => switch (input) {
            'k', 'q', 's', 't', 'h', 'm', 'y', 'r', 'w', 'g', 'j', 'z', 'd', 'b', 'p', 'c' => |v| {
                self.current_state = .{ .SingleConsonant = v };
                try self.appendChar(v);
            },
            'n' => {
                try self.appendChar('n');
                self.current_state = .NConsonant;
            },
            'a', 'i', 'u', 'e', 'o' => |v| {
                try self.appendKana(&[1]u8{v});
                self.resetState();
            },
            'l', 'x' => |v| {
                try self.appendChar(v);
                self.current_small_state = true;
            },
            else => {},
        },
        .SingleConsonant => |consonant| switch (input) {
            'a', 'i', 'u', 'e', 'o' => |v| {
                self.removeLast(1);
                try self.appendKana(&[2]u8{ consonant, v });
                self.resetState();
            },
            'y' => {
                if (consonant == 'y') {
                    try self.output.appendSlice("っ");
                    self.current_state = .{ .SingleConsonant = 'y' };
                } else {
                    self.current_state = .{ .PalatalizedConsonant = consonant };
                }
            },
            'n' => {
                try self.appendChar('n');
                self.current_state = .NConsonant;
            },
            'k', 'q', 's', 't', 'h', 'm', 'r', 'w', 'g', 'j', 'z', 'd', 'b', 'p' => |v| {
                if (v == consonant) {
                    self.removeLast(1);
                    try self.output.appendSlice("っ");
                    self.current_state = .{ .SingleConsonant = v };
                } else if (consonant == 'c' and v == 'h') {
                    self.current_state = .ChConsonant;
                } else if (consonant == 't' and v == 's') {
                    self.current_state = .TsConsonant;
                } else if (consonant == 't' and v == 'h') {
                    self.current_state = .ThConsonant;
                } else if (consonant == 's' and v == 'h') {
                    self.current_state = .ShConsonant;
                } else {
                    self.current_state = .{ .SingleConsonant = v };
                }
                try self.appendChar(v);
            },
            'l', 'x' => |v| {
                try self.appendChar(v);
                self.current_small_state = true;
                self.current_state = .Start;
            },
            else => self.resetState(),
        },
        .PalatalizedConsonant => |consonant| switch (input) {
            'a', 'i', 'u', 'e', 'o' => |v| {
                self.removeLast(2);
                try self.appendKana(&[3]u8{ consonant, 'y', v });
                self.resetState();
            },
            'l', 'x' => |v| {
                try self.appendChar(v);
                self.current_small_state = true;
                self.current_state = .Start;
            },
            else => self.resetState(),
        },
        .NConsonant => switch (input) {
            'a', 'i', 'u', 'e', 'o' => |v| {
                self.removeLast(1);
                try self.appendKana(&[2]u8{ 'n', v });
                self.resetState();
            },
            'y' => {
                try self.appendChar('y');
                self.current_state = .{ .PalatalizedConsonant = 'n' };
            },
            'k', 'q', 's', 't', 'h', 'm', 'r', 'w', 'g', 'j', 'z', 'd', 'b', 'p', 'c' => |v| {
                self.removeLast(1);
                try self.appendKana(&[1]u8{'n'});
                try self.appendChar(v);
                self.current_state = .{ .SingleConsonant = v };
            },
            'n' => {
                self.removeLast(1);
                try self.appendKana(&[1]u8{'n'});
                self.resetState();
            },
            'l', 'x' => |v| {
                try self.appendChar(v);
                self.current_small_state = true;
                self.current_state = .Start;
            },
            else => self.resetState(),
            // - Standalone → Output ん.
        },
        .ChConsonant => switch (input) {
            'a', 'i', 'u', 'e', 'o' => |v| {
                self.removeLast(2);
                try self.appendKana(&[3]u8{ 'c', 'h', v });
                self.resetState();
            },
            'l', 'x' => |v| {
                try self.appendChar(v);
                self.current_small_state = true;
                self.current_state = .Start;
            },
            else => {
                try self.appendChar(input);
                self.resetState();
            },
        },
        .TsConsonant => switch (input) {
            'a', 'i', 'u', 'e', 'o' => |v| {
                self.removeLast(2);
                try self.appendKana(&[3]u8{ 't', 's', v });
                self.resetState();
            },
            'l', 'x' => |v| {
                try self.appendChar(v);
                self.current_small_state = true;
                self.current_state = .Start;
            },
            else => {
                try self.appendChar(input);
                self.resetState();
            },
        },
        .ThConsonant => switch (input) {
            'a', 'i', 'u', 'e', 'o' => |v| {
                self.removeLast(2);
                try self.appendKana(&[3]u8{ 't', 'h', v });
                self.resetState();
            },
            'l', 'x' => |v| {
                try self.appendChar(v);
                self.current_small_state = true;
                self.current_state = .Start;
            },
            else => {
                try self.appendChar(input);
                self.resetState();
            },
        },
        .ShConsonant => switch (input) {
            'a', 'i', 'u', 'e', 'o' => |v| {
                self.removeLast(2);
                try self.appendKana(&[3]u8{ 's', 'h', v });
                self.resetState();
            },
            'l', 'x' => |v| {
                try self.appendChar(v);
                self.current_small_state = true;
                self.current_state = .Start;
            },
            else => {
                try self.appendChar(input);
                self.resetState();
            },
        },
    }

    return .{ .input = self.input.items, .output = self.output.items };
}

fn resetState(self: *Self) void {
    self.current_state = .Start;
    self.current_small_state = false;
}

fn getHiragana(self: *Self, key: []const u8) ?[]const u8 {
    if (self.current_small_state) {
        self.removeLast(1);
        return small_hiragana_map.get(key) orelse hiragana_map.get(key);
    }
    return hiragana_map.get(key);
}

fn appendKana(self: *Self, romaji: []const u8) !void {
    if (self.getHiragana(romaji)) |kana| {
        try self.output.appendSlice(kana);
    }
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
