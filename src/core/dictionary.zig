const std = @import("std");
const mem = std.mem;

const WordEntry = @import("WordEntry.zig");
const datastructs = @import("datastructs");
const LoudsTrie = datastructs.louds_trie.LoudsTrie;
const SuccinctBitArray = datastructs.succinct_bit_array.SuccinctBitArray;
const SuccinctBitArrayBuilder = datastructs.succinct_bit_array.SuccinctBitArrayBuilder;
const Louds = datastructs.louds.Louds;
const BitArray = datastructs.BitArray;

pub const Dictionary = struct {
    trie: LoudsTrie(WordEntry),
    costs: std.ArrayList(isize),
    right_count: usize,

    pub fn deinit(self: *Dictionary) void {
        self.trie.deinit();
        self.costs.deinit();
    }

    pub fn getCost(self: Dictionary, left_id: usize, right_id: usize) isize {
        return self.costs.items[self.right_count * left_id + right_id];
    }
};

// TODO: take a look at decompressor/compressor https://codeberg.org/atman/zg/src/branch/master/src/CaseData.zig

/// A serializer/deserializer for Dictionary.
/// The deserializer assumes that the lifetime of the reader's underlying buffer will outlive
/// the deserialized object, as it uses slices directly from the reader's buffer rather than
/// allocating new strings. This is safe when using @embedFile since the embedded data lives
/// for the entire program lifetime.
pub const DictionarySerializer = struct {
    const Self = @This();

    pub fn serialize(dict: *const Dictionary, writer: anytype) !void {
        // dict.ltrie.labels
        try serializeStringArrayList(&dict.trie.labels, writer);
        // dict.ltrie.values
        try serializeWordEntryArrayList(&dict.trie.values, writer);
        // dict.ltrie.value_offsets
        try serializeIntArrayList(usize, &dict.trie.value_offsets, writer);
        // dict.ltrie.louds.sba
        try serializeSuccinctBitArray(&dict.trie.louds.sba, writer);
        // dict.costs
        try serializeIntArrayList(isize, &dict.costs, writer);
        // dict.right_count
        try writer.writeInt(usize, dict.right_count, .little);
    }

    pub fn deserialize(allocator: mem.Allocator, reader: anytype) !Dictionary {
        var labels = try deserializeStringArrayList(allocator, reader);
        errdefer labels.deinit();
        var values = try deserializeWordEntryArrayList(allocator, reader);
        errdefer values.deinit();
        var value_offsets = try deserializeIntArrayList(usize, allocator, reader);
        errdefer value_offsets.deinit();
        var louds_sba = try deserializeSuccinctBitArray(allocator, reader);
        errdefer louds_sba.deinit();
        var costs = try deserializeIntArrayList(isize, allocator, reader);
        errdefer costs.deinit();
        const right_count = try reader.readInt(usize, .little);
        return .{
            .trie = .{
                .labels = labels,
                .values = values,
                .value_offsets = value_offsets,
                .louds = Louds(32).init(louds_sba),
            },
            .costs = costs,
            .right_count = right_count,
        };
    }

    fn serializeStringArrayList(list: *const std.ArrayList([]const u8), writer: anytype) !void {
        // First write the number of elements in the array
        try writer.writeInt(usize, list.items.len, .little);

        // For each element (which is []const u8)
        for (list.items) |str| {
            // Write number of bytes in this array
            try writer.writeInt(usize, str.len, .little);

            try writer.writeAll(str);
        }
    }

    fn serializeWordEntryArrayList(list: *const std.ArrayList(WordEntry), writer: anytype) !void {
        // First write the number of elements in the array
        try writer.writeInt(usize, list.items.len, .little);

        // For each element (which is WordEntry)
        for (list.items) |we| {
            try serializeWordEntry(we, writer);
        }
    }

    fn serializeWordEntry(we: WordEntry, writer: anytype) !void {
        try writer.writeInt(usize, we.word.len, .little);
        try writer.writeAll(we.word);
        try writer.writeInt(usize, we.left_id, .little);
        try writer.writeInt(usize, we.right_id, .little);
        try writer.writeInt(isize, we.cost, .little);
    }

    fn serializeSuccinctBitArray(sba: *const SuccinctBitArray(32), writer: anytype) !void {
        // serialize sba.bit_array
        try serializeBitArray(&sba.bit_array, writer);
        // serialize sba.index
        try serializeIntArrayList(usize, &sba.index, writer);
    }

    fn serializeBitArray(array: *const BitArray, writer: anytype) !void {
        // bit_len: usize,
        try writer.writeInt(usize, array.bit_len, .little);
        // bytes: std.ArrayList(u8),
        try serializeIntArrayList(u8, &array.bytes, writer);
    }

    fn serializeIntArrayList(comptime T: type, list: *const std.ArrayList(T), writer: anytype) !void {
        // First write the number of elements in the array
        try writer.writeInt(usize, list.items.len, .little);

        // For each element (which is usize)
        for (list.items) |element| {
            // Write it
            try writer.writeInt(T, element, .little);
        }
    }

    fn deserializeStringArrayList(allocator: mem.Allocator, reader: anytype) !std.ArrayList([]const u8) {
        var list = std.ArrayList([]const u8).init(allocator);
        errdefer list.deinit();

        // Read number of elements
        const num_elements = try reader.readInt(usize, .little);

        // Allocate space for all elements
        try list.ensureTotalCapacity(num_elements);

        // For each element
        var i: usize = 0;
        while (i < num_elements) : (i += 1) {
            // Read string length
            const str_len = try reader.readInt(usize, .little);

            // Read string
            const str = reader.context.buffer[reader.context.pos .. reader.context.pos + str_len];
            try reader.skipBytes(str_len, .{});

            try list.append(str);
        }

        return list;
    }

    fn deserializeWordEntryArrayList(allocator: mem.Allocator, reader: anytype) !std.ArrayList(WordEntry) {
        var list = std.ArrayList(WordEntry).init(allocator);
        errdefer list.deinit();

        // Read number of elements
        const num_elements = try reader.readInt(usize, .little);

        // Allocate space for all elements
        try list.ensureTotalCapacity(num_elements);

        // For each element
        var i: usize = 0;
        while (i < num_elements) : (i += 1) {
            const we = try deserializeWordEntry(reader);
            try list.append(we);
        }

        return list;
    }

    fn deserializeWordEntry(reader: anytype) !WordEntry {
        const str_len = try reader.readInt(usize, .little);
        const word = reader.context.buffer[reader.context.pos .. reader.context.pos + str_len];
        try reader.skipBytes(str_len, .{});
        const left_id = try reader.readInt(usize, .little);
        const right_id = try reader.readInt(usize, .little);
        const cost = try reader.readInt(isize, .little);
        return .{
            .word = word,
            .left_id = left_id,
            .right_id = right_id,
            .cost = cost,
        };
    }

    fn deserializeSuccinctBitArray(allocator: mem.Allocator, reader: anytype) !SuccinctBitArray(32) {
        return .{
            .bit_array = try deserializeBitArray(allocator, reader),
            .index = try deserializeIntArrayList(usize, allocator, reader),
        };
    }

    fn deserializeBitArray(allocator: mem.Allocator, reader: anytype) !BitArray {
        return .{
            .bit_len = try reader.readInt(usize, .little),
            .bytes = try deserializeIntArrayList(u8, allocator, reader),
        };
    }

    fn deserializeIntArrayList(comptime T: type, allocator: mem.Allocator, reader: anytype) !std.ArrayList(T) {
        var list = std.ArrayList(T).init(allocator);
        errdefer list.deinit();

        // First read the number of elements in the array
        const num_elements = try reader.readInt(usize, .little);

        // Allocate space for all elements
        try list.ensureTotalCapacity(num_elements);

        // For each element
        var i: usize = 0;
        while (i < num_elements) : (i += 1) {
            // Read the element
            const element = try reader.readInt(T, .little);

            try list.append(element);
        }

        return list;
    }
};
