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
    PalatalizedConsonant: struct { u8, ?u8 },
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
            },
            'n' => self.current_state = .NConsonant,
            'a', 'i', 'u', 'e', 'o' => |v| {
                try self.appendKana(&[1]u8{v});
                self.goToStart();
            },
            'l', 'x' => {
                self.current_small_state = true;
            },
            else => {},
        },
        .SingleConsonant => |consonant| switch (input) {
            'a', 'i', 'u', 'e', 'o' => |v| {
                try self.appendKana(&[2]u8{ consonant, v });
                self.goToStart();
            },
            'y' => {
                if (consonant == 'y') {
                    try self.output.appendSlice("っ");
                    self.current_state = .{ .SingleConsonant = 'y' };
                } else {
                    self.current_state = .{ .PalatalizedConsonant = .{ consonant, null } };
                }
            },
            'k', 'q', 's', 't', 'h', 'm', 'r', 'w', 'g', 'j', 'z', 'd', 'b', 'p' => |v| {
                if (v == consonant) {
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
            },
            else => self.goToStart(),
        },
        .PalatalizedConsonant => |consonant| switch (input) {
            'a', 'i', 'u', 'e', 'o' => |v| {
                if (consonant.@"1" == null) {
                    try self.appendKana(&[3]u8{ consonant.@"0", 'y', v });
                } else {
                    try self.appendKana(&[4]u8{ consonant.@"0", consonant.@"1".?, 'y', v });
                }
                self.goToStart();
            },
            else => self.goToStart(),
        },
        .NConsonant => switch (input) {
            'a', 'i', 'u', 'e', 'o' => |v| {
                try self.appendKana(&[2]u8{ 'n', v });
                self.goToStart();
            },
            'y' => {
                self.current_state = .{ .PalatalizedConsonant = .{ 'n', null } };
            },
            'k', 'q', 's', 't', 'h', 'm', 'r', 'w', 'g', 'j', 'z', 'd', 'b', 'p', 'c' => |v| {
                try self.appendKana(&[1]u8{'n'});
                self.current_state = .{ .SingleConsonant = v };
            },
            'n' => {
                try self.appendKana(&[1]u8{'n'});
                self.goToStart();
            },
            else => self.goToStart(),
            // - Standalone → Output ん.
        },
        .ChConsonant => switch (input) {
            'a', 'i', 'u', 'e', 'o' => |v| {
                try self.appendKana(&[3]u8{ 'c', 'h', v });
                self.goToStart();
            },
            'y' => {
                self.current_state = .{ .PalatalizedConsonant = .{ 'c', 'h' } };
            },
            else => self.goToStart(),
        },
        .TsConsonant => switch (input) {
            'a', 'i', 'u', 'e', 'o' => |v| {
                try self.appendKana(&[3]u8{ 't', 's', v });
                self.goToStart();
            },
            's' => {
                self.current_state = .{ .PalatalizedConsonant = .{ 't', 's' } };
            },
            else => self.goToStart(),
        },
        .ThConsonant => switch (input) {
            'a', 'i', 'u', 'e', 'o' => |v| {
                try self.appendKana(&[3]u8{ 't', 'h', v });
                self.goToStart();
            },
            'h' => {
                self.current_state = .{ .PalatalizedConsonant = .{ 't', 'h' } };
            },
            else => self.goToStart(),
        },
        .ShConsonant => switch (input) {
            'a', 'i', 'u', 'e', 'o' => |v| {
                try self.appendKana(&[3]u8{ 's', 'h', v });
                self.goToStart();
            },
            'h' => {
                self.current_state = .{ .PalatalizedConsonant = .{ 's', 'h' } };
            },
            else => self.goToStart(),
        },
    }

    return .{ .input = self.input.items, .output = self.output.items };
}

fn goToStart(self: *Self) void {
    self.current_state = .Start;
    self.current_small_state = false;
}

fn getHiragana(self: Self, key: []const u8) ?[]const u8 {
    if (self.current_small_state) {
        return small_hiragana_map.get(key) orelse hiragana_map.get(key);
    }
    return hiragana_map.get(key);
}

fn appendKana(self: *Self, romaji: []const u8) !void {
    if (self.getHiragana(romaji)) |kana| {
        try self.output.appendSlice(kana);
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
