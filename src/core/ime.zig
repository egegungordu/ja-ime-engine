const std = @import("std");
const mem = std.mem;
const unicode = std.unicode;

const WordEntry = @import("WordEntry.zig");
const Dictionary = @import("dictionary.zig").Dictionary;
const trans = @import("transliteration.zig");
const lattice = @import("lattice.zig");
const datastructs = @import("datastructs");
const utf8utils = @import("utf8utils");
const utf8 = utf8utils.utf8;
const Utf8Input = utf8utils.Utf8Input;

pub fn Ime(
    /// Dictionary loader is a type that implements loadDictionary and freeDictionary functions.
    /// loadDictionary takes an allocator and returns a Dictionary that contains dictionary entries and costs.
    /// freeDictionary takes a Dictionary pointer and frees the dictionary.
    /// If dict_loader is null, no dictionary will be loaded and dictionary lookups will be disabled.
    dict_loader: anytype,
) type {
    return struct {
        allocator: mem.Allocator,
        input: Utf8Input,
        dict: ?Dictionary,
        best_path: ?[]WordEntry,

        const Self = @This();

        pub fn init(allocator: mem.Allocator) !Self {
            const dict: ?Dictionary = blk: {
                if (@TypeOf(dict_loader) != type) break :blk null;
                break :blk try dict_loader.loadDictionary(allocator);
            };

            return Self{
                .allocator = allocator,
                .input = Utf8Input.init(allocator),
                .dict = dict,
                .best_path = null,
            };
        }

        pub fn deinit(self: *Self) void {
            self.input.deinit();
            if (self.dict != null and @TypeOf(dict_loader) == type) {
                dict_loader.freeDictionary(&self.dict.?);
                self.dict = null;
            }
            if (self.best_path) |best_path| {
                self.allocator.free(best_path);
                self.best_path = null;
            }
        }

        pub const MatchModification = struct {
            deleted_codepoints: usize,
            inserted_text: []const u8,
        };

        /// Inserts a slice into the input buffer, doing transliteration if possible.
        /// Only accepts one valid UTF-8 character at a time.
        pub fn insert(self: *Self, s: []const u8) !?MatchModification {
            const full_width_match = try self.tryFullWidthMatch(s) orelse return null;
            const transliterable = self.peekBackTransliterable(4) orelse return full_width_match;
            var it = utf8.createUtf8ShrinkingIterator(transliterable.slice);

            const modification = blk: while (it.next()) |segment| {
                if (try self.tryKanaMatch(segment)) |modification| {
                    break :blk modification;
                }
            } else break :blk full_width_match;

            try self.updateMatches();

            return modification;
        }

        // TODO: support multiple best matches
        pub fn getMatches(self: Self) ?[]WordEntry {
            return self.best_path;
        }

        // TODO: this will take an index when multiple matches are supported
        // TODO: also can return info about what kind of match it was (predictive/full etc)
        pub fn applyMatch(self: *Self) !?MatchModification {
            if (self.best_path) |best_path| {
                var new_items = std.ArrayList(u8).init(self.allocator);
                defer new_items.deinit();
                for (best_path) |entry| {
                    try new_items.appendSlice(entry.word);
                }
                var view = unicode.Utf8View.initUnchecked(self.input.buf.items);
                var it = view.iterator();
                var codepoint_len: usize = 0;
                while (it.nextCodepoint()) |_| {
                    codepoint_len += 1;
                }
                try self.input.replaceBack(codepoint_len, new_items.items);
                return .{ .deleted_codepoints = codepoint_len, .inserted_text = new_items.items };
            }
            return null;
        }

        pub fn clear(self: *Self) void {
            self.input.clear();
        }

        pub fn moveCursorForward(self: *Self, n: usize) void {
            self.input.moveCursorForward(n);
        }

        pub fn moveCursorBack(self: *Self, n: usize) void {
            self.input.moveCursorBack(n);
        }

        pub fn deleteBack(self: *Self) !void {
            self.input.deleteBack(1);
            try self.updateMatches();
        }

        pub fn deleteForward(self: *Self) !void {
            self.input.deleteForward(1);
            try self.updateMatches();
        }

        fn updateMatches(self: *Self) !void {
            if (self.best_path) |best_path| {
                self.allocator.free(best_path);
            }

            if (self.dict) |dict| {
                var ltc = try lattice.createLattice(self.allocator, self.input.buf.items, &dict);
                defer ltc.deinit();
                self.best_path = try ltc.findBestPath(&dict);
            }
        }

        const PeekBackTransliterableResult = struct {
            slice: []const u8,
            codepoint_len: usize,
        };

        /// Peeks back n characters in the input buffer and returns the biggest transliterable slice.
        ///
        /// Example (n = 2):
        /// - "hello" -> .{ "lo", 2 }
        /// - "んg" -> .{ "g", 1 }
        fn peekBackTransliterable(self: *Self, n: usize) ?PeekBackTransliterableResult {
            var total_bytes: usize = 0;
            var total_codepoint_len: usize = 0;
            var last_slice: []const u8 = undefined;
            for (0..n) |i| {
                const peeked = self.input.peekBackOne(i);
                if (peeked.codepoint_len == 0 or !isTransliterable(peeked.slice)) {
                    if (total_bytes == 0) return null;
                    return PeekBackTransliterableResult{
                        .slice = @as([*]const u8, @ptrCast(last_slice.ptr))[0..total_bytes],
                        .codepoint_len = total_codepoint_len,
                    };
                }
                total_codepoint_len += peeked.codepoint_len;
                total_bytes += peeked.slice.len;
                last_slice = peeked.slice;
            }
            if (total_bytes == 0) return null;
            return PeekBackTransliterableResult{
                .slice = @as([*]const u8, @ptrCast(last_slice))[0..total_bytes],
                .codepoint_len = total_codepoint_len,
            };
        }

        fn tryFullWidthMatch(self: *Self, s: []const u8) !?MatchModification {
            if (getFullWidthMatch(s)) |match| {
                try self.input.insert(match);
                return .{
                    .deleted_codepoints = 0,
                    .inserted_text = match,
                };
            }
            return null;
        }

        /// Transliterates kana matches
        ///
        /// - ｋｕ -> く
        /// - ｋｙｏ -> きょ
        /// - ａ -> あ
        fn tryKanaMatch(self: *Self, segment: utf8.Segment) !?MatchModification {
            if (getKanaMatch(segment.it.bytes)) |match| {
                try self.input.replaceBack(segment.codepoint_len, match);
                return .{
                    .deleted_codepoints = if (segment.codepoint_len > 1) segment.codepoint_len - 1 else 0,
                    .inserted_text = match,
                };
            }
            return null;
        }
    };
}

fn isTransliterable(s: []const u8) bool {
    return trans.transliterables.get(s) != null;
}

fn getKanaMatch(s: []const u8) ?[]const u8 {
    return trans.transliteration_map.get(s);
}

fn getFullWidthMatch(s: []const u8) ?[]const u8 {
    return trans.full_width_map.get(s);
}
