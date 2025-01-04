const std = @import("std");
const mem = std.mem;
const RomajiParseFsm = @import("RomajiParseFsm.zig");
const Result = RomajiParseFsm.Result;

pub fn parseRomaji(allocator: mem.Allocator, input: []const u8) ![]const u8 {
    var fsm = try RomajiParseFsm.init(allocator);
    defer fsm.deinit();

    for (input) |c| {
        _ = try fsm.process(c);
    }

    return try fsm.output.toOwnedSlice();
}

test "basic parsing" {
    const allocator = std.testing.allocator;

    const input = "konnnichiha";

    const result = try parseRomaji(allocator, input);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("こんにちは", result);
}
