const std = @import("std");
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
