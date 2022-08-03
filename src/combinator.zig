const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;

const testing = std.testing;
const debug = std.debug;
const assert = debug.assert;
const Parser = @import("parser.zig");
const character = @import("character.zig");

// current matched values
// const head = res.value[0]
// const list = res.value[1..]
pub const ParseValue = union(enum) {
    Leaf: [2]u8,
    Level: ArrayList(*ParseValue),
};

pub const ParseError = error{InvalidArg};

pub const ParseResult = struct {
    state: bool,
    value: ?ParseValue,
    // info
    desc: ?[]const u8,
    // index failed to parse
    index: ?u32,
    // remaining char values
    next_index: u32,
};

pub fn success(value: ?ParseValue, next: u32) ParseResult {
    return ParseResult{ .state = true, .value = value, .next_index = next, .desc = null, .index = null };
}

pub fn fail(desc: []const u8, index: u32, next_index: u32) ParseResult {
    return ParseResult{
        .state = false,
        .desc = desc,
        .index = index,
        .next_index = next_index,
        .value = null,
    };
}

const BUF_CAP: u32 = 8 * (1 << 10);

// helper for generate one-char parser
pub fn GenerateCharParser(
    comptime desc: []const u8,
    comptime parseFn: fn (byte: u8) bool,
) type {
    return struct {
        pub fn parse(bytes: []const u8, index: u32) ParseResult {
            if (bytes.len == 0) {
                return fail("empty string", index, index);
            }
            if (index < bytes.len and parseFn(bytes[index])) {
                return success(ParseValue{ .Leaf = [2]u32{ index, index + 1 } }, index + 1);
            }
            return fail(desc, index, index);
        }
    };
}

// optional
// optional(parser) -> a new parser
pub fn Optional(comptime parser: type) type {
    return struct {
        pub fn parse(bytes: []const u8, index: u32) ParseResult {
            const res = parser.parse(bytes, index);
            if (res.state) {
                if (res.value) |value| {
                    return success(value, res.next_index);
                }
            }
            return success(ParseValue{ .Leaf = [2]u32{ index, index } }, index);
        }
    };
}

/// const p1 = digit;
/// const p2 = letter;
/// const p = andThen(p1,p2);
/// p.parse("12") -> failure
/// const p3 = andThen(p1,p1);
/// p3.parse("12") -> success
pub fn AndThen(comptime p1: type, comptime p2: type) type {
    return struct {
        pub fn parse(bytes: []const u8, index: u32) ParseResult {
            const res1 = p1.parse(bytes, index);
            if (res1.state) {
                const res2 = p2.parse(bytes, res1.next_index);
                if (res2.state) {
                    if (res2.value) |value| {
                        // return ((r1,r2), i2)
                        return success([2]u32{ index, value[1] }, res2.next_index);
                    } else {
                        // ((r1,None),i2)
                        if (res1.value) |value| {
                            return success([2]u32{ index, value[1] }, res2.next_index);
                        } else {
                            // ((None,None),i2)
                            return success(null, res2.next_index);
                        }
                    }
                }
            }
            return fail("andThen", index, index);
        }
    };
}

/// const p1 = digit;
/// const p2 = letter;
/// const p = OrElse(p1,p2);
/// p.parse("a") -> p2.parse("a")
pub fn OrElse(comptime p1: type, comptime p2: type) type {
    return struct {
        pub fn parse(bytes: []const u8, index: u32) ParseResult {
            const res1 = p1.parse(bytes, index);
            if (res1.state) {
                return res1;
            }
            return p2.parse(bytes, index);
        }
    };
}

// zero or many times
// many(parser) -> a new parser
pub fn Many(comptime p: type) type {
    return struct {
        pub fn parse(bytes: []const u8, index: u32) ParseResult {
            var res = p.parse(bytes, index);
            while (res.state) {
                const next = p.parse(bytes, res.next_index);
                if (!next.state) {
                    if (res.value) |value| {
                        return success([2]u32{ index, value[1] }, res.next_index);
                    }
                }
                res = next;
            }
            return success([2]u32{ index, index }, index);
        }
    };
}

// at least one time or many times
// andThen(p, many(p))
pub fn ManyOne(comptime p: type) type {
    return AndThen(p, Many(p));
}

// [min,max]
pub fn Times(comptime p: type, min: u32, max: u32) ParseError!type {
    if (min > max) {
        return ParseError.InvalidArg;
    }
    return struct {
        pub fn parse(bytes: []const u8, index: u32) ParseResult {
            var res = p.parse(bytes, index);
            var count: u32 = if (res.state) 1 else 0;
            while (res.state and count < max) {
                const next = p.parse(bytes, res.next_index);
                if (!next.state) {
                    break;
                }
                count += 1;
                res = next;
            }
            if (res.state and count >= min and count <= max) {
                if (res.value) |value| {
                    return success([2]u32{ index, value[1] }, res.next_index);
                }
            }
            return fail("invalid Times", index, index);
        }
    };
}

pub const Digit = GenerateCharParser("digit", character.isDigit);
pub const Letter = GenerateCharParser("string", character.isAlpha);


test "test digit" {
    var res = Digit.parse("1234", 0);
    debug.print("{}\n", .{res});
    try testing.expect(res.state);
    if (res.value) |value| {
        const expect = [_]u32{ 0, 1 };
        try testing.expect(std.mem.eql(u32, value[0..2], expect[0..2]));
    }
    res = Digit.parse("abcd", 0);
    try testing.expect(!res.state);
    try testing.expect(res.value == null);
}

test "test andThen" {
    const twoDigit = AndThen(Digit, Digit);
    const p = AndThen(twoDigit, Letter);
    var res = p.parse("1234", 0);
    debug.print("{}\n", .{res});
    try testing.expect(!res.state);
    try testing.expect(res.next_index == 0);
    res = p.parse("12a4", 0);
    try testing.expect(res.state);
    try testing.expect(res.next_index == 3);
    const p2 = AndThen(p, Digit);
    res = p2.parse("12a4", 0);
    try testing.expect(res.state);
    try testing.expect(res.next_index == 4);
}

test "test orElse" {
    const twoLetter = AndThen(Letter, Letter);
    const twoDigit = AndThen(Digit, Digit);
    const twoLetterOrTwoDigit = OrElse(twoLetter, twoDigit);
    var res = twoLetterOrTwoDigit.parse("a2333", 0);
    try testing.expect(!res.state);
    try testing.expect(res.next_index == 0);
    res = twoLetterOrTwoDigit.parse("2333a", 0);
    try testing.expect(res.state);
    try testing.expect(res.next_index == 2);
    res = twoLetterOrTwoDigit.parse("aa22", 0);
    try testing.expect(res.state);
    try testing.expect(res.next_index == 2);
}

test "test many" {
    const manyLetter = Many(Letter);
    const manyDigit = Many(Digit);
    var res = manyDigit.parse("111aaa", 0);
    try testing.expect(res.state);
    try testing.expect(res.next_index == 3);
    res = manyLetter.parse("111aaa", 0);
    try testing.expect(res.state);
    try testing.expect(res.next_index == 0);
    const p = AndThen(manyDigit, manyLetter);
    res = p.parse("111aaa", 0);
    try testing.expect(res.state);
    try testing.expect(res.next_index == 6);
}

test "test optional" {
    const optionalLetter = Optional(Letter);
    const manyDigit = Many(Digit);
    const p = AndThen(manyDigit, optionalLetter);
    var res = p.parse("1111", 0);
    try testing.expect(res.state);
    try testing.expect(res.next_index == 4);
    res = p.parse("1111a", 0);
    try testing.expect(res.state);
    try testing.expect(res.next_index == 5);
    res = p.parse("aaa111", 0);
    debug.print("{}\n", .{res});
    try testing.expect(res.state);
    try testing.expect(res.next_index == 1);
}

test "test times" {
    const threeDigits = try Times(Digit, 3, 3);
    var res = threeDigits.parse("111", 0);
    debug.print("{}", .{res});
    try testing.expect(res.state);
    try testing.expect(res.next_index == 3);
    res = threeDigits.parse("11", 0);
    try testing.expect(!res.state);
    try testing.expect(res.next_index == 0);
    const oneOrTwoDigits = try Times(Digit, 1, 2);
    res = oneOrTwoDigits.parse("1111", 0);
    try testing.expect(res.state);
    try testing.expect(res.next_index == 2);
}

test "test combined andThen" {
    const DotParser = GenerateCharParser("dot", isDot);
    const p = AndThen(Letter, (AndThen(Optional(DotParser), Optional(Digit))));
    var res = p.parse("a2b", 0);
    debug.print("{} \n", .{res});
    try testing.expect(res.state);
    res = p.parse("ab.2", 0);
    debug.print("{} \n", .{res});
    try testing.expect(res.state);
    if (res.value) |value| {
        try testing.expect(value[0] == 0);
        try testing.expect(value[1] == 1);
    }
}
