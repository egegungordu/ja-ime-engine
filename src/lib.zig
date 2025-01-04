const std = @import("std");
const mem = std.mem;
const hiragana_map = @import("hiragana.zig").TransliterationMap;

pub fn processInput(allocator: mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);

    var i: usize = 0;
    var j: usize = hiragana_map.max_len;

    while (j <= input.len) {
        const slice = input[i..j];
        if (hiragana_map.get(slice)) |match| {
            try result.appendSlice(match);
            i = j;
            j = j + hiragana_map.max_len;
        } else {
            j -= 1;
            if (i == j) {
                i += 1;
                j = i + hiragana_map.max_len;
                try result.appendSlice(slice);
            }
        }
    }
    return result.toOwnedSlice();
}
