const std = @import("std");
const mem = std.mem;
const unicode = std.unicode;

const Ime = @import("ime_core.zig").Ime;

/// Transliterates a utf-8 encoded string from romaji to hiragana/full-width characters.
/// Returns a new allocated string.
pub fn toKana(allocator: mem.Allocator, s: []const u8) ![]const u8 {
    var ime = try Ime(null).init(allocator);
    defer ime.deinit();

    var it = unicode.Utf8View.initUnchecked(s).iterator();
    while (it.nextCodepointSlice()) |slice| {
        _ = try ime.insert(slice);
    }

    return allocator.dupe(u8, ime.input.buf.items);
}

/// Transliterates a utf-8 encoded string from romaji to hiragana/full-width characters.
/// Uses the provided buffer to do the conversion.
pub fn toKanaBuf(buf: []u8, s: []const u8) ![]const u8 {
    var fba = std.heap.FixedBufferAllocator.init(buf);
    const allocator = fba.allocator();

    var ime = try Ime(null).init(allocator);

    var it = unicode.Utf8View.initUnchecked(s).iterator();
    while (it.nextCodepointSlice()) |slice| {
        _ = try ime.insert(slice);
    }

    return ime.input.buf.items;
}

const testing = std.testing;

test "toKana" {
    const res = try toKana(testing.allocator, "beibi-");
    defer testing.allocator.free(res);

    try testing.expectEqualStrings("べいびー", res);
}

test "toKanaBuf" {
    var buf: [100]u8 = undefined;
    const res = try toKanaBuf(&buf, "beibi-");

    try testing.expectEqualStrings("べいびー", res);
}
