const std = @import("std");

extern "debug" fn consoleLog(arg: u32) void;

const Ime = @import("Ime.zig").Ime;

var ime: Ime(.borrowed) = undefined;

// Buffer for input text
var input_buffer = std.mem.zeroes([64]u8);
export fn getInputBufferPointer() [*]u8 {
    return @ptrCast(&input_buffer);
}

// Buffer for the ime
var ime_buffer = std.mem.zeroes([2048]u8);
var last_insert_result: ?Ime(.borrowed).MatchModification = undefined;

export fn init() void {
    ime = Ime(.borrowed).init(&ime_buffer);
}

export fn insert(length: usize) void {
    const slice = input_buffer[0..length];
    last_insert_result = ime.insert(slice) catch return;
}

export fn getDeletedCodepoints() usize {
    return if (last_insert_result) |result| result.deleted_codepoints else 0;
}

export fn getInsertedTextLength() usize {
    return if (last_insert_result) |result| result.inserted_text.len else 0;
}

export fn getInsertedTextPointer() [*]const u8 {
    return @ptrCast(if (last_insert_result) |result| result.inserted_text.ptr else undefined);
}

export fn deleteBack() void {
    ime.deleteBack();
}

export fn deleteForward() void {
    ime.deleteForward();
}

export fn moveCursorBack(n: usize) void {
    ime.moveCursorBack(n);
}

export fn moveCursorForward(n: usize) void {
    ime.moveCursorForward(n);
}
