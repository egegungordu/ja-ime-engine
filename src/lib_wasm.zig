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
var last_insert_result: Ime(.borrowed).InsertResult = undefined;

export fn init() void {
    ime = Ime(.borrowed).init(&ime_buffer);
}

export fn insert(length: usize) void {
    const slice = input_buffer[0..length];
    last_insert_result = ime.insert(slice) catch return;
}

export fn getDeletedCodepoints() usize {
    return last_insert_result.deleted_codepoints;
}

export fn getDeletionDirection() u8 {
    if (last_insert_result.deletion_direction) |direction| {
        return switch (direction) {
            .forward => 1,
            .backward => 2,
        };
    }
    return 0;
}

export fn getInsertedTextLength() usize {
    return last_insert_result.inserted_text.len;
}

export fn getInsertedTextPointer() [*]const u8 {
    return @ptrCast(last_insert_result.inserted_text.ptr);
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
