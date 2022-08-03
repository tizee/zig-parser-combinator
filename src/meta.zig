const std = @import("std");
const meta = std.meta;
const print = std.debug.print;
// Generic Result Interface
pub fn Result(comptime I: type, comptime O: type) type {
    return struct { input: I = undefined, output: O = undefined };
}

pub fn assertSameType(desc: []const u8, a: anytype, b: anytype) void {
    if (@TypeOf(a) != @TypeOf(b)) {
        @compileError(desc);
    }
}

pub fn assertFn(desc: []const u8, s: anytype) void {
    if (@typeInfo(@TypeOf(s)) != .Fn) {
        @compileError(desc ++ "required fn type");
    }
}

pub fn assertStruct(desc: []const u8, s: anytype) void {
    if (@typeInfo(@TypeOf(s)) != .Struct) {
        @compileError(desc ++ "require struct type");
    }
}

pub fn ReturnType(F: anytype) type {
    return @typeInfo(@TypeOf(F)).Fn.return_type.?;
}

pub fn printFields(s: anytype) void {
    assertStruct("PrintFields", s);
    const fields = @typeInfo(@TypeOf(s)).Struct.fields;

    // name type: value
    inline for (fields) |field| {
        print("{s}\t type:{any}\t value:{any}\n", .{ field.name, field.field_type, @field(s, field.name) });
    }
}

test "printFields" {
    const S = struct {
        a: u32,
        b: bool,
    };
    printFields(S{
        .a = 10,
        .b = false,
    });
}
