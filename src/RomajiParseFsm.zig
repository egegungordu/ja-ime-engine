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
            'k', 's', 't', 'h', 'm', 'y', 'r', 'w', 'g', 'j', 'z', 'd', 'b', 'p', 'c' => |v| {
                self.current_state = .{ .SingleConsonant = v };
            },
            'n' => self.current_state = .NConsonant,
            'a', 'i', 'u', 'e', 'o' => |v| {
                const val = self.getHiragana(&[1]u8{v});
                try self.output.appendSlice(val);
                self.goToStart();
            },
            'l', 'x' => {
                self.current_small_state = true;
            },
            else => {},
        },
        .SingleConsonant => |consonant| switch (input) {
            'a', 'i', 'u', 'e', 'o' => |v| {
                const combined_val = self.getHiragana(&[2]u8{ consonant, v });
                try self.output.appendSlice(combined_val);
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
            'k', 's', 't', 'h', 'm', 'r', 'w', 'g', 'j', 'z', 'd', 'b', 'p' => |v| {
                if (v == consonant) {
                    try self.output.appendSlice("っ");
                    self.current_state = .{ .SingleConsonant = v };
                } else if (consonant == 'c' and v == 'h') {
                    self.current_state = .ChConsonant;
                } else if (consonant == 't' and v == 's') {
                    self.current_state = .TsConsonant;
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
                const combined_val = blk: {
                    if (consonant.@"1" == null) {
                        break :blk self.getHiragana(&[3]u8{ consonant.@"0", 'y', v });
                    } else {
                        break :blk self.getHiragana(&[4]u8{ consonant.@"0", consonant.@"1".?, 'y', v });
                    }
                };
                try self.output.appendSlice(combined_val);
                self.goToStart();
            },
            else => self.goToStart(),
        },
        .NConsonant => switch (input) {
            'a', 'i', 'u', 'e', 'o' => |v| {
                const combined_val = self.getHiragana(&[2]u8{ 'n', v });
                try self.output.appendSlice(combined_val);
                self.goToStart();
            },
            'y' => {
                self.current_state = .{ .PalatalizedConsonant = .{ 'n', null } };
            },
            'k', 's', 't', 'h', 'm', 'r', 'w', 'g', 'j', 'z', 'd', 'b', 'p', 'c' => |v| {
                const val = self.getHiragana(&[1]u8{'n'});
                try self.output.appendSlice(val);
                self.current_state = .{ .SingleConsonant = v };
            },
            'n' => {
                const val = self.getHiragana(&[1]u8{'n'});
                try self.output.appendSlice(val);
                self.goToStart();
            },
            else => self.goToStart(),
            // - Standalone → Output ん.
        },
        .ChConsonant => switch (input) {
            'a', 'i', 'u', 'e', 'o' => |v| {
                const combined_val = self.getHiragana(&[3]u8{ 'c', 'h', v });
                try self.output.appendSlice(combined_val);
                self.goToStart();
            },
            'y' => {
                self.current_state = .{ .PalatalizedConsonant = .{ 'c', 'h' } };
            },
            else => self.goToStart(),
        },
        .TsConsonant => switch (input) {
            'a', 'i', 'u', 'e', 'o' => |v| {
                const combined_val = self.getHiragana(&[3]u8{ 't', 's', v });
                try self.output.appendSlice(combined_val);
                self.goToStart();
            },
            's' => {
                self.current_state = .{ .PalatalizedConsonant = .{ 't', 's' } };
            },
            else => self.goToStart(),
        },
        .ShConsonant => switch (input) {
            'a', 'i', 'u', 'e', 'o' => |v| {
                const combined_val = self.getHiragana(&[3]u8{ 's', 'h', v });
                try self.output.appendSlice(combined_val);
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

fn getHiragana(self: Self, key: []const u8) []const u8 {
    if (self.current_small_state) {
        return small_hiragana_map.get(key) orelse hiragana_map.get(key).?;
    }
    return hiragana_map.get(key).?;
}
