const std = @import("std");
const mem = std.mem;
const heap = std.heap;
const ime = @import("lib.zig");
const RomajiParseFsm = @import("RomajiParseFsm.zig");

pub fn main() !void {
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();

    var fsm = try RomajiParseFsm.init(arena.allocator());

    const input = "yarerumonnnarayattemiro";

    for (input) |c| {
        const result = try fsm.process(c);
        std.debug.print("\nin: {s}\nout:{s}\n", .{ result.input, result.output });
    }
}
