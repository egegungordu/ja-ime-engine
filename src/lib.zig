const std = @import("std");
const mem = std.mem;
const unicode = std.unicode;

pub const Ime = @import("core/Ime.zig").Ime;

/// Transliterates a string from romaji to hiragana/full-width character.
/// Uses the provided buffer to do the conversion.
pub fn bufConvert(buf: []u8, s: []const u8) ![]const u8 {
    var ime = Ime(.borrowed).init(buf);

    var it = unicode.Utf8View.initUnchecked(s).iterator();
    while (it.nextCodepointSlice()) |slice| {
        _ = try ime.insert(slice);
    }

    return ime.input.buf.items();
}

/// Transliterates a string from romaji to hiragana/full-width character.
/// Returns a new allocated string.
pub fn allocConvert(allocator: mem.Allocator, s: []const u8) ![]const u8 {
    var ime = Ime(.owned).init(allocator);
    defer ime.deinit();

    var it = unicode.Utf8View.initUnchecked(s).iterator();
    while (it.nextCodepointSlice()) |slice| {
        _ = try ime.insert(slice);
    }

    return allocator.dupe(u8, ime.input.buf.items());
}

test "bufConvert" {
    var buf: [100]u8 = undefined;
    const res = try bufConvert(&buf, "beibi-");

    try std.testing.expectEqualSlices(u8, res, "べいびー");
}

test "allocConvert" {
    const res = try allocConvert(std.testing.allocator, "beibi-");
    defer std.testing.allocator.free(res);

    try std.testing.expectEqualSlices(u8, res, "べいびー");
}
