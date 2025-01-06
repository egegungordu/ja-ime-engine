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

pub const PeekResult = struct {
    slice: []const u8,
    codepoint_len: usize,
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

    pub fn peekForward(it: *Utf8BidirectionalIterator, n: usize) PeekResult {
        const original_i = it.i;
        defer it.i = original_i;

        var end_ix = original_i;
        var found: usize = 0;
        while (found < n) : (found += 1) {
            const next_codepoint = it.nextCodepointSlice() orelse return .{
                .slice = it.bytes[original_i..],
                .codepoint_len = found,
            };
            end_ix += next_codepoint.len;
        }

        return .{
            .slice = it.bytes[original_i..end_ix],
            .codepoint_len = found,
        };
    }

    pub fn peekBack(it: *Utf8BidirectionalIterator, n: usize) PeekResult {
        const original_i = it.i;
        defer it.i = original_i;

        var start_ix = original_i;
        var found: usize = 0;
        while (found < n) : (found += 1) {
            const prev_codepoint = it.prevCodepointSlice() orelse return .{
                .slice = it.bytes[start_ix..original_i],
                .codepoint_len = found,
            };
            start_ix -= prev_codepoint.len;
        }

        return .{
            .slice = it.bytes[start_ix..original_i],
            .codepoint_len = found,
        };
    }
};

pub fn createUtf8ShrinkingIterator(s: []const u8) Utf8ShrinkingIterator {
    var it = unicode.Utf8View.initUnchecked(s).iterator();
    var codepoint_len: usize = 0;
    while (it.nextCodepointSlice()) |_| {
        codepoint_len += 1;
    }
    return Utf8ShrinkingIterator{
        .codepoint_len = codepoint_len,
        .bytes = s,
    };
}

pub const Segment = struct {
    it: unicode.Utf8Iterator,
    codepoint_len: usize,
};

pub const Utf8ShrinkingIterator = struct {
    codepoint_len: usize,
    bytes: []const u8,
    i: usize = 0,

    pub fn next(self: *Utf8ShrinkingIterator) ?Segment {
        if (self.i >= self.bytes.len) {
            return null;
        }
        var it = unicode.Utf8View.initUnchecked(self.bytes[self.i..]).iterator();

        const candidate = Segment{
            .it = it,
            .codepoint_len = self.codepoint_len,
        };

        _ = it.nextCodepoint() orelse return null;
        self.codepoint_len -= 1;
        self.i += it.i;

        return candidate;
    }
};

test "utf8: bidirectional - kanji iteration" {
    const s = Utf8BidirectionalView.initUnchecked("東京市");

    var it1 = s.iterator();
    try testing.expectEqualStrings(it1.nextCodepointSlice().?, "東");
    try testing.expectEqualStrings(it1.nextCodepointSlice().?, "京");
    try testing.expectEqualStrings(it1.nextCodepointSlice().?, "市");
    try testing.expect(it1.nextCodepointSlice() == null);
    try testing.expectEqualStrings(it1.prevCodepointSlice().?, "市");
    try testing.expectEqualStrings(it1.prevCodepointSlice().?, "京");
    try testing.expectEqualStrings(it1.prevCodepointSlice().?, "東");
    try testing.expect(it1.prevCodepointSlice() == null);

    var it2 = s.iterator();
    try testing.expectEqual(it2.nextCodepoint().?, 0x6771);
    try testing.expectEqual(it2.nextCodepoint().?, 0x4eac);
    try testing.expectEqual(it2.nextCodepoint().?, 0x5e02);
    try testing.expect(it2.nextCodepoint() == null);
    try testing.expectEqual(it2.prevCodepoint().?, 0x5e02);
    try testing.expectEqual(it2.prevCodepoint().?, 0x4eac);
    try testing.expectEqual(it2.prevCodepoint().?, 0x6771);
    try testing.expect(it2.prevCodepoint() == null);
}

test "utf8: bidirectional - ascii iteration" {
    const s = Utf8BidirectionalView.initUnchecked("abc");

    var it1 = s.iterator();
    try testing.expectEqualStrings(it1.nextCodepointSlice().?, "a");
    try testing.expectEqualStrings(it1.nextCodepointSlice().?, "b");
    try testing.expectEqualStrings(it1.nextCodepointSlice().?, "c");
    try testing.expect(it1.nextCodepointSlice() == null);
    try testing.expectEqualStrings(it1.prevCodepointSlice().?, "c");
    try testing.expectEqualStrings(it1.prevCodepointSlice().?, "b");
    try testing.expectEqualStrings(it1.prevCodepointSlice().?, "a");
    try testing.expect(it1.prevCodepointSlice() == null);

    var it2 = s.iterator();
    try testing.expectEqual(it2.nextCodepoint().?, 'a');
    try testing.expectEqual(it2.nextCodepoint().?, 'b');
    try testing.expectEqual(it2.nextCodepoint().?, 'c');
    try testing.expect(it2.nextCodepoint() == null);
    try testing.expectEqual(it2.prevCodepoint().?, 'c');
    try testing.expectEqual(it2.prevCodepoint().?, 'b');
    try testing.expectEqual(it2.prevCodepoint().?, 'a');
    try testing.expect(it2.prevCodepoint() == null);
}

test "utf8: bidirectional - mixed text iteration" {
    const s = Utf8BidirectionalView.initUnchecked("リズムにyeah");
    var it = s.iterator();
    try testing.expectEqualStrings(it.nextCodepointSlice().?, "リ");
    try testing.expectEqualStrings(it.nextCodepointSlice().?, "ズ");
    try testing.expectEqualStrings(it.nextCodepointSlice().?, "ム");
    try testing.expectEqualStrings(it.nextCodepointSlice().?, "に");
    try testing.expectEqualStrings(it.nextCodepointSlice().?, "y");
    try testing.expectEqualStrings(it.nextCodepointSlice().?, "e");
    try testing.expectEqualStrings(it.nextCodepointSlice().?, "a");
    try testing.expectEqualStrings(it.nextCodepointSlice().?, "h");
    try testing.expect(it.nextCodepointSlice() == null);
    try testing.expectEqualStrings(it.prevCodepointSlice().?, "h");
    try testing.expectEqualStrings(it.prevCodepointSlice().?, "a");
    try testing.expectEqualStrings(it.prevCodepointSlice().?, "e");
    try testing.expectEqualStrings(it.prevCodepointSlice().?, "y");
    try testing.expectEqualStrings(it.prevCodepointSlice().?, "に");
    try testing.expectEqualStrings(it.prevCodepointSlice().?, "ム");
    try testing.expectEqualStrings(it.prevCodepointSlice().?, "ズ");
    try testing.expectEqualStrings(it.prevCodepointSlice().?, "リ");
    try testing.expect(it.prevCodepointSlice() == null);
}

test "utf8: bidirectional - peek operations" {
    const s = Utf8BidirectionalView.initUnchecked("てtoらpoっど");
    var it = s.iterator();
    try testing.expectEqualStrings("て", it.peekForward(1).slice);
    try testing.expectEqualStrings("てt", it.peekForward(2).slice);
    try testing.expectEqualStrings("てto", it.peekForward(3).slice);
    try testing.expectEqualStrings("てtoら", it.peekForward(4).slice);
    try testing.expectEqualStrings("てtoらp", it.peekForward(5).slice);
    try testing.expectEqualStrings("てtoらpo", it.peekForward(6).slice);
    try testing.expectEqualStrings("てtoらpoっ", it.peekForward(7).slice);
    try testing.expectEqualStrings("てtoらpoっど", it.peekForward(8).slice);
    try testing.expectEqualStrings("てtoらpoっど", it.peekForward(99999).slice);
    try testing.expectEqual(8, it.peekForward(99999).codepoint_len);
    _ = it.nextCodepointSlice();
    _ = it.nextCodepointSlice();
    _ = it.nextCodepointSlice();
    _ = it.nextCodepointSlice();
    try testing.expectEqualStrings("ら", it.peekBack(1).slice);
    try testing.expectEqualStrings("oら", it.peekBack(2).slice);
    try testing.expectEqualStrings("toら", it.peekBack(3).slice);
    try testing.expectEqualStrings("てtoら", it.peekBack(4).slice);
    try testing.expectEqualStrings("てtoら", it.peekBack(99999).slice);
    try testing.expectEqual(4, it.peekBack(99999).codepoint_len);
}

test "utf8: shrinking - basic iteration" {
    const s = "きょうは";
    var it = createUtf8ShrinkingIterator(s);

    // First iteration: "きょうは"
    if (it.next()) |segment| {
        try testing.expectEqualStrings("きょうは", segment.it.bytes);
        try testing.expectEqual(@as(usize, 4), segment.codepoint_len);
    } else {
        try testing.expect(false);
    }

    // Second iteration: "ょうは"
    if (it.next()) |segment| {
        try testing.expectEqualStrings("ょうは", segment.it.bytes);
        try testing.expectEqual(@as(usize, 3), segment.codepoint_len);
    } else {
        try testing.expect(false);
    }

    // Third iteration: "うは"
    if (it.next()) |segment| {
        try testing.expectEqualStrings("うは", segment.it.bytes);
        try testing.expectEqual(@as(usize, 2), segment.codepoint_len);
    } else {
        try testing.expect(false);
    }

    // Fourth iteration: "は"
    if (it.next()) |segment| {
        try testing.expectEqualStrings("は", segment.it.bytes);
        try testing.expectEqual(@as(usize, 1), segment.codepoint_len);
    } else {
        try testing.expect(false);
    }

    // Fourth iteration: should be null
    try testing.expect(it.next() == null);
}
