const std = @import("std");
const ParserUtils = @import("parser.zig");
const ParseError = ParserUtils.ParseError;
const Parser = ParserUtils.Parser;

const meta = @import("meta.zig");
const Result = meta.Result;

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const ArrayHashMap = std.ArrayHashMap;

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

pub fn isSpace(ch: u8) bool {
    return ch == ' ' or ch == '\t';
}

pub fn isDot(byte: u8) bool {
    return byte == '.';
}

pub fn isGreater(byte: u8) bool {
    return byte == '>';
}

pub fn isAsterisk(byte: u8) bool {
    return byte == '*';
}

pub fn isSharp(byte: u8) bool {
    return byte == '#';
}

const PredictFn = fn (u8) bool;

// basic character parser generator
pub fn SatisfyParser(predictFn: PredictFn) type {
    return struct {
        const Self = @This();
        pub const InputType = []const u8;
        pub const OutputType = u8;
        pub const ResultType = Result(InputType, OutputType);

        pub fn init(allocator: ?Allocator) Self {
            _ = allocator;
            return Self{};
        }

        pub fn parse(self: *Self, input: InputType) ParseError!ResultType {
            _ = self;
            if (input.len == 0) {
                return ParseError.NotEnoughInput;
            }

            if (predictFn(input[0])) {
                return ResultType{ .input = input[1..], .output = input[0] };
            }
            return ParseError.InvalidInput;
        }
    };
}

const DigitParser = SatisfyParser(isDigit);
const AlphaParser = SatisfyParser(isAlpha);

pub const Digit = Parser(DigitParser);
pub const Alpha = Parser(AlphaParser);

const testing = std.testing;
const shouldPassAll = @import("test-utils.zig").shouldPassAll;

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

test "test Digit and Char" {
    const word: []const u8 = "abcd";
    const word2: []const u8 = "1234";

    var parser = Alpha.init(null);
    try shouldPassAll(parser, word);
    var parser2 = Digit.init(null);
    try shouldPassAll(parser2, word2);
}

test "test Digit with map" {
    const word: []const u8 = "1234";
    const toDigit = struct {
        pub fn toDigit(value: u8) u32 {
            return value - '0';
        }
    }.toDigit;
    var parser = ParserUtils.Map(Digit, toDigit).init(null);
    var res = try parser.parse(word);

    try testing.expectEqual(@as(u32, 1), res.output);
    res = try parser.parse(res.input);
    try testing.expectEqual(@as(u32, 2), res.output);
    res = try parser.parse(res.input);
    try testing.expectEqual(@as(u32, 3), res.output);
    res = try parser.parse(res.input);
    try testing.expectEqual(@as(u32, 4), res.output);
}

test "test Digit,Alpha with Or" {
    const word: []const u8 = "1a2b3c4d";
    var parser = ParserUtils.Or(Alpha, Digit).init(null);
    try shouldPassAll(parser, word);
}

test "test Digit,Alpha with And" {
    const word: []const u8 = "1122";
    var parser = ParserUtils.And(Digit, Digit).init(null);
    var res = try parser.parse(word);
    try testing.expectEqual(res.output.@"0", '1');
    try testing.expectEqual(res.output.@"1", '1');
    res = try parser.parse(res.input);
    try testing.expectEqual(res.output.@"0", '2');
    try testing.expectEqual(res.output.@"1", '2');
}

test "test Digit with Many" {
    const word: []const u8 = "0123456789";
    const allocator = testing.allocator;
    var parser = ParserUtils.Many(Digit).init(allocator);
    errdefer parser.deinit();
    defer parser.deinit();
    var res = try parser.parse(word);
    try testing.expectEqual(res.output.items.len, 10);
    try testing.expect(std.mem.eql(u8, res.output.items, word));

    const word2: []const u8 = "1234";
    res = try parser.parse(word2);
    try testing.expectEqual(res.output.items.len, 4);
    try testing.expect(std.mem.eql(u8, res.output.items, word2));
}

test "test Digit with ManyOne" {
    const word: []const u8 = "0123456789";
    const allocator = testing.allocator;
    var parser = ParserUtils.Many(Digit).init(allocator);
    errdefer parser.deinit();
    defer parser.deinit();
    var res = try parser.parse(word);
    try testing.expectEqual(res.output.items.len, 10);
    try testing.expect(std.mem.eql(u8, res.output.items, word));

    const word2: []const u8 = "1234";
    res = try parser.parse(word2);
    try testing.expectEqual(res.output.items.len, 4);
    try testing.expect(std.mem.eql(u8, res.output.items, word2));
}
