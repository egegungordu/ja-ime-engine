const std = @import("std");
const mem = std.mem;

const core = @import("core");
const ImeCore = core.ime.Ime;
const Dictionary = core.dictionary.Dictionary;
const DictionarySerializer = core.dictionary.DictionarySerializer;

const ipadic_bytes = @embedFile("ipadic");

const IpadicLoader = struct {
    pub fn loadDictionary(allocator: mem.Allocator) !Dictionary {
        var dict_fbs = std.io.fixedBufferStream(ipadic_bytes);

        return try DictionarySerializer.deserialize(
            allocator,
            dict_fbs.reader(),
        );
    }

    pub fn freeDictionary(dict: *Dictionary) void {
        dict.deinit();
    }
};

pub const Ime = ImeCore(IpadicLoader);
pub const WordEntry = core.WordEntry;
