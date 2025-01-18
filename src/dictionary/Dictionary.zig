const std = @import("std");
const mem = std.mem;

pub const Dictionary = struct {
    entries: std.ArrayList([]const u8),
    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator) !Dictionary {
        const dict = @embedFile("combined_dictionary.tsv");
        var lines = std.mem.splitScalar(u8, dict, '\n');
        var entries = std.ArrayList([]const u8).init(allocator);

        while (lines.next()) |line| {
            var it = std.mem.splitScalar(u8, line, '\t');
            const reading = it.next().?;
            _ = it.next();
            _ = it.next();
            _ = it.next();
            const word = it.next();
            if (word) |w| {
                try entries.append(try allocator.dupe(u8, reading));
                try entries.append(try allocator.dupe(u8, w));
            }
        }

        return Dictionary{
            .entries = entries,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Dictionary) void {
        for (self.entries.items) |item| {
            self.allocator.free(item);
        }
        self.entries.deinit();
    }

    pub fn iterator(self: Dictionary) DictionaryIterator {
        return .{ .it = std.mem.window([]const u8, self.entries.items, 2, 2) };
    }
};

pub const DictionaryIterator = struct {
    it: std.mem.WindowIterator([]const u8),

    pub fn next(self: *DictionaryIterator) ?[]const []const u8 {
        return self.it.next();
    }
};
