const std = @import("std");

pub const vowels = createSet("aiueo");
pub const consonants = createSet("kqsthmyrvwgjzdbpc");
pub const small_markers = createSet("lx");

fn createSet(comptime chars: []const u8) std.StaticBitSet(128) {
    var set = std.StaticBitSet(128).initEmpty();
    for (chars) |c| {
        set.set(c);
    }
    return set;
}
