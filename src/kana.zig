const std = @import("std");
const mem = std.mem;
const unicode = std.unicode;

const Ime = @import("core").ime.Ime;

/// Transliterates a utf-8 encoded string from romaji to hiragana/full-width characters.
/// Returns a new allocated string.
pub fn convert(allocator: mem.Allocator, s: []const u8) ![]const u8 {
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
pub fn convertBuf(buf: []u8, s: []const u8) ![]const u8 {
    var fba = std.heap.FixedBufferAllocator.init(buf);
    const allocator = fba.allocator();

    var ime = try Ime(null).init(allocator);

    var it = unicode.Utf8View.initUnchecked(s).iterator();
    while (it.nextCodepointSlice()) |slice| {
        _ = try ime.insert(slice);
    }

    return ime.input.buf.items;
}
