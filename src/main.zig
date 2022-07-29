const std = @import("std");
const testing = std.testing;

pub fn isAlpha(ch: u8) bool {
    return switch (ch) {
        'a'...'z' => true,
        'A'...'Z' => true,
        else => false,
    };
}

pub fn isDigit(ch: u8) bool {
    return switch (ch) {
        '0'...'9' => true,
        else => false,
    };
}

pub const ParseError = error{InvalidArg};
pub const ParseResult = struct {
    // success or failure
    state: bool,
    // overflow
    overflow: bool,
    // next index
    index: u32,
    // captured char values
    value: std.ArrayList(u8),
    // failure info
    desc: []const u8,
    pub fn success(byte: u8, index: u32) ParseResult {
        return ParseResult{ .state = true, .index = index, .value = byte, .desc = "", .overflow = false };
    }

    pub fn fail(desc: []const u8, index: u32, overflow: bool) ParseResult {
        return ParseResult{ .state = false, .index = index, .value = 0, .desc = desc, .overflow = overflow };
    }
};

// helper for generate one-char parser
pub fn GenerateCharParser(comptime desc: []const u8, comptime parseFn: fn (byte: u8) bool) type {
    return struct {
        pub fn parse(bytes: []const u8, index: u32) ParseResult {
            if (index < bytes.len and parseFn(bytes[index])) {
                return ParseResult.success(bytes[index], index + 1);
            }
            return ParseResult.fail(desc, index, index >= bytes.len);
        }
    };
}

// optional
// optional(parser) -> a new parser
pub fn Optional(comptime parser: type) type {
    return struct {
        pub fn parse(bytes: []const u8, index: u32) ParseResult {
            const res = parser.parse(bytes, index);
            if (!res.state) {
                return ParseResult.success(0, res.index);
            }
            return ParseResult.success(res.value, res.index);
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
                const res2 = p2.parse(bytes, res1.index);
                return res2;
            }
            return res1;
        }
    };
}

/// const p1 = digit;
/// const p2 = letter;
/// const p = andThen(p1,p2);
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
                res = p.parse(bytes, res.index);
            }
            return ParseResult.success(res.value, res.index);
        }
    };
}

// at least one time or many times
// andThen(p, many(p))
pub fn ManyOne(comptime p: type) type {
    return AndThen(p, Many(p));
}

pub fn Times(comptime p: type, min: u32, max: u32) ParseError!type {
    if (min > max) {
        return ParseError.InvalidArg;
    }
    return struct {
        pub fn parse(bytes: []const u8, index: u32) ParseResult {
            var res = p.parse(bytes, index);
            var count: u32 = if (res.state) 1 else 0;
            while (res.state and count < max) {
                res = p.parse(bytes, res.index);
                if (res.state) {
                    count += 1;
                }
            }
            if (count < min) {
                return ParseResult.fail("times is insufficient or failed", res.index, res.overflow);
            }
            if (count >= min and count <= max) {
                return ParseResult.success(res.value, res.index);
            }
            return res;
        }
    };
}

pub const Digit = GenerateCharParser("digit", isDigit);
pub const Letter = GenerateCharParser("string", isAlpha);

test "test isAlpha" {
    var ch: u8 = 'a';
    while (ch < 'z' + 1) {
        try testing.expect(isAlpha(ch));
        ch += 1;
    }
    ch = 'A';
    while (ch < 'Z' + 1) {
        try testing.expect(isAlpha(ch));
        ch += 1;
    }
    try testing.expect(!isAlpha('0'));
    try testing.expect(!isAlpha('1'));
}

test "test isDigit" {
    var ch: u8 = '0';
    while (ch < '9' + 1) {
        try testing.expect(isDigit(ch));
        ch += 1;
    }
    ch = 'A';
    while (ch < 'Z' + 1) {
        try testing.expect(!isDigit(ch));
        ch += 1;
    }
}

test "test digit" {
    var res = Digit.parse("1234", 0);
    try testing.expect(res.state);
    res = Digit.parse("abcd", 0);
    try testing.expect(!res.state);
}

test "test andThen" {
    const twoDigit = AndThen(Digit, Digit);
    const p = AndThen(twoDigit, Letter);
    var res = p.parse("1234", 0);
    try testing.expect(!res.state);
    try testing.expect(res.index == 2);
    res = p.parse("12a4", 0);
    try testing.expect(res.state);
    try testing.expect(res.index == 3);
    const p2 = AndThen(p, Digit);
    res = p2.parse("12a4", 0);
    try testing.expect(res.state);
    try testing.expect(res.index == 4);
}

test "test orElse" {
    const twoLetter = AndThen(Letter, Letter);
    const twoDigit = AndThen(Digit, Digit);
    const twoLetterOrTwoDigit = OrElse(twoLetter, twoDigit);
    var res = twoLetterOrTwoDigit.parse("a2333", 0);
    try testing.expect(!res.state);
    try testing.expect(res.index == 0);
    res = twoLetterOrTwoDigit.parse("2333a", 0);
    try testing.expect(res.state);
    try testing.expect(res.index == 2);
    res = twoLetterOrTwoDigit.parse("aa22", 0);
    try testing.expect(res.state);
    try testing.expect(res.index == 2);
}

test "test many" {
    const manyLetter = Many(Letter);
    const manyDigit = Many(Digit);
    var res = manyDigit.parse("111aaa", 0);
    try testing.expect(res.state);
    try testing.expect(res.index == 3);
    res = manyLetter.parse("111aaa", 0);
    try testing.expect(res.state);
    try testing.expect(res.index == 0);
    const p = AndThen(manyDigit, manyLetter);
    res = p.parse("111aaa", 0);
    try testing.expect(res.state);
    try testing.expect(res.index == 6);
}

test "test optional" {
    const optionalLetter = Optional(Letter);
    const manyDigit = Many(Digit);
    const p = AndThen(manyDigit, optionalLetter);
    var res = p.parse("1111", 0);
    try testing.expect(res.state);
    try testing.expect(res.index == 4);
    res = p.parse("1111a", 0);
    try testing.expect(res.state);
    try testing.expect(res.index == 5);
    res = p.parse("aaa111", 0);
    try testing.expect(res.state);
    try testing.expect(res.index == 1);
}

test "test times" {
    const threeDigits = try Times(Digit, 3, 3);
    var res = threeDigits.parse("111", 0);
    std.debug.print("{}", .{res});
    try testing.expect(res.state);
    try testing.expect(res.index == 3);
    res = threeDigits.parse("11", 0);
    try testing.expect(!res.state);
    try testing.expect(res.index == 2);
    const oneOrTwoDigits = try Times(Digit, 1, 2);
    res = oneOrTwoDigits.parse("1111", 0);
    try testing.expect(res.state);
    try testing.expect(res.index == 2);
}
