const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const unicode = std.unicode;

pub const Utf8BidirectionalView = struct {
    bytes: []const u8,

    pub fn initUnchecked(s: []const u8) Utf8BidirectionalView {
        return .{ .bytes = s };
    }

    pub fn iterator(s: Utf8BidirectionalView) Utf8BidirectionalIterator {
        return Utf8BidirectionalIterator{
            .bytes = s.bytes,
            .i = 0,
        };
    }
};

pub const Utf8BidirectionalIterator = struct {
    bytes: []const u8,
    i: usize,

    pub fn nextCodepointSlice(it: *Utf8BidirectionalIterator) ?[]const u8 {
        if (it.i >= it.bytes.len) {
            return null;
        }

        const cp_len = unicode.utf8ByteSequenceLength(it.bytes[it.i]) catch unreachable;
        it.i += cp_len;
        return it.bytes[it.i - cp_len .. it.i];
    }

    pub fn nextCodepoint(it: *Utf8BidirectionalIterator) ?u21 {
        const slice = it.nextCodepointSlice() orelse return null;
        return unicode.utf8Decode(slice) catch unreachable;
    }

    pub fn prevCodepointSlice(it: *Utf8BidirectionalIterator) ?[]const u8 {
        if (it.i == 0) {
            return null;
        }

        var start_index: usize = it.i - 1;

        // Find the start of the codepoint by skipping continuation bytes
        while (start_index > 0 and (it.bytes[start_index] & 0b1100_0000) == 0b1000_0000) {
            start_index -= 1;
        }

        // Validate the start byte and calculate the codepoint length
        const cp_len = unicode.utf8ByteSequenceLength(it.bytes[start_index]) catch return null;

        // Ensure the calculated codepoint length fits within bounds
        if (start_index + cp_len > it.i) {
            return null; // Invalid sequence or out of bounds
        }

        it.i = start_index;
        return it.bytes[start_index .. start_index + cp_len];
    }

    pub fn prevCodepoint(it: *Utf8BidirectionalIterator) ?u21 {
        const slice = it.prevCodepointSlice() orelse return null;
        return unicode.utf8Decode(slice) catch unreachable;
    }

    pub fn peekForward(it: *Utf8BidirectionalIterator, n: usize) []const u8 {
        const original_i = it.i;
        defer it.i = original_i;

        var end_ix = original_i;
        var found: usize = 0;
        while (found < n) : (found += 1) {
            const next_codepoint = it.nextCodepointSlice() orelse return it.bytes[original_i..];
            end_ix += next_codepoint.len;
        }

        return it.bytes[original_i..end_ix];
    }

    pub fn peekBackward(it: *Utf8BidirectionalIterator, n: usize) []const u8 {
        const original_i = it.i;
        defer it.i = original_i;

        var start_ix = original_i;
        var found: usize = 0;
        while (found < n) : (found += 1) {
            const prev_codepoint = it.prevCodepointSlice() orelse return it.bytes[start_ix..original_i];
            start_ix -= prev_codepoint.len;
        }

        return it.bytes[start_ix..original_i];
    }
};

test "utf8 bidirectional view on kanji" {
    const s = Utf8BidirectionalView.initUnchecked("東京市");

    var it1 = s.iterator();
    try testing.expect(mem.eql(u8, "東", it1.nextCodepointSlice().?));
    try testing.expect(mem.eql(u8, "京", it1.nextCodepointSlice().?));
    try testing.expect(mem.eql(u8, "市", it1.nextCodepointSlice().?));
    try testing.expect(it1.nextCodepointSlice() == null);
    try testing.expect(mem.eql(u8, "市", it1.prevCodepointSlice().?));
    try testing.expect(mem.eql(u8, "京", it1.prevCodepointSlice().?));
    try testing.expect(mem.eql(u8, "東", it1.prevCodepointSlice().?));
    try testing.expect(it1.prevCodepointSlice() == null);

    var it2 = s.iterator();
    try testing.expect(it2.nextCodepoint().? == 0x6771);
    try testing.expect(it2.nextCodepoint().? == 0x4eac);
    try testing.expect(it2.nextCodepoint().? == 0x5e02);
    try testing.expect(it2.nextCodepoint() == null);
    try testing.expect(it2.prevCodepoint().? == 0x5e02);
    try testing.expect(it2.prevCodepoint().? == 0x4eac);
    try testing.expect(it2.prevCodepoint().? == 0x6771);
    try testing.expect(it2.prevCodepoint() == null);
}

test "utf8 bidirectional view on ascii" {
    const s = Utf8BidirectionalView.initUnchecked("abc");

    var it1 = s.iterator();
    try testing.expect(mem.eql(u8, "a", it1.nextCodepointSlice().?));
    try testing.expect(mem.eql(u8, "b", it1.nextCodepointSlice().?));
    try testing.expect(mem.eql(u8, "c", it1.nextCodepointSlice().?));
    try testing.expect(it1.nextCodepointSlice() == null);
    try testing.expect(mem.eql(u8, "c", it1.prevCodepointSlice().?));
    try testing.expect(mem.eql(u8, "b", it1.prevCodepointSlice().?));
    try testing.expect(mem.eql(u8, "a", it1.prevCodepointSlice().?));
    try testing.expect(it1.prevCodepointSlice() == null);

    var it2 = s.iterator();
    try testing.expect(it2.nextCodepoint().? == 'a');
    try testing.expect(it2.nextCodepoint().? == 'b');
    try testing.expect(it2.nextCodepoint().? == 'c');
    try testing.expect(it2.nextCodepoint() == null);
    try testing.expect(it2.prevCodepoint().? == 'c');
    try testing.expect(it2.prevCodepoint().? == 'b');
    try testing.expect(it2.prevCodepoint().? == 'a');
    try testing.expect(it2.prevCodepoint() == null);
}

test "utf8 bidirectional view on mixed" {
    const s = Utf8BidirectionalView.initUnchecked("リズムにyeah");
    var it = s.iterator();
    try testing.expect(mem.eql(u8, "リ", it.nextCodepointSlice().?));
    try testing.expect(mem.eql(u8, "ズ", it.nextCodepointSlice().?));
    try testing.expect(mem.eql(u8, "ム", it.nextCodepointSlice().?));
    try testing.expect(mem.eql(u8, "に", it.nextCodepointSlice().?));
    try testing.expect(mem.eql(u8, "y", it.nextCodepointSlice().?));
    try testing.expect(mem.eql(u8, "e", it.nextCodepointSlice().?));
    try testing.expect(mem.eql(u8, "a", it.nextCodepointSlice().?));
    try testing.expect(mem.eql(u8, "h", it.nextCodepointSlice().?));
    try testing.expect(it.nextCodepointSlice() == null);
    try testing.expect(mem.eql(u8, "h", it.prevCodepointSlice().?));
    try testing.expect(mem.eql(u8, "a", it.prevCodepointSlice().?));
    try testing.expect(mem.eql(u8, "e", it.prevCodepointSlice().?));
    try testing.expect(mem.eql(u8, "y", it.prevCodepointSlice().?));
    try testing.expect(mem.eql(u8, "に", it.prevCodepointSlice().?));
    try testing.expect(mem.eql(u8, "ム", it.prevCodepointSlice().?));
    try testing.expect(mem.eql(u8, "ズ", it.prevCodepointSlice().?));
    try testing.expect(mem.eql(u8, "リ", it.prevCodepointSlice().?));
    try testing.expect(it.prevCodepointSlice() == null);
}

test "utf8 bidirectional view peek" {
    const s = Utf8BidirectionalView.initUnchecked("てtoらpoっど");
    var it = s.iterator();
    try testing.expect(mem.eql(u8, "て", it.peekForward(1)));
    try testing.expect(mem.eql(u8, "てt", it.peekForward(2)));
    try testing.expect(mem.eql(u8, "てto", it.peekForward(3)));
    try testing.expect(mem.eql(u8, "てtoら", it.peekForward(4)));
    try testing.expect(mem.eql(u8, "てtoらp", it.peekForward(5)));
    try testing.expect(mem.eql(u8, "てtoらpo", it.peekForward(6)));
    try testing.expect(mem.eql(u8, "てtoらpoっ", it.peekForward(7)));
    try testing.expect(mem.eql(u8, "てtoらpoっど", it.peekForward(8)));
    try testing.expect(mem.eql(u8, "てtoらpoっど", it.peekForward(99999)));
    _ = it.nextCodepointSlice();
    _ = it.nextCodepointSlice();
    _ = it.nextCodepointSlice();
    _ = it.nextCodepointSlice();
    try testing.expect(mem.eql(u8, "ら", it.peekBackward(1)));
    try testing.expect(mem.eql(u8, "oら", it.peekBackward(2)));
    try testing.expect(mem.eql(u8, "toら", it.peekBackward(3)));
    try testing.expect(mem.eql(u8, "てtoら", it.peekBackward(4)));
    try testing.expect(mem.eql(u8, "てtoら", it.peekBackward(99999)));
}
