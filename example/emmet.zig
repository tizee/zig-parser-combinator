const std = @import("std");
const testing = std.testing;
const combinator = @import("parser-combinator");
fn isDot(byte: u8) bool {
    return byte == '.';
}

fn isGreater(byte: u8) bool {
    return byte == '>';
}

fn isAsterisk(byte: u8) bool {
    return byte == '*';
}

fn isSharp(byte: u8) bool {
    return byte == '#';
}

const DotParser = combinator.GenerateCharParser("dot", isDot);
const AsterisParser = combinator.GenerateCharParser("asterisk", isAsterisk);
const GreaterParser = combinator.GenerateCharParser("greater", isGreater);
const SharpParser = combinator.GenerateCharParser("sharp", isSharp);

const LabelParser = struct {
    pub fn parse(bytes: []const u8, index: u32) []const u8 {
        const p = combinator.ManyOne(combinator.Letter);
        var res = p.parse(bytes, index);
        return bytes[index..res.index];
    }
};

const NumberParser = struct {
    pub fn parse(bytes: []const u8, index: u32) combinator.ParseResult {
        const p = combinator.ManyOne(combinator.Digit);
        var res = p.parse(bytes, index);
        return bytes[index..res.index];
    }
};

pub fn RightOnly(comptime left: type, comptime right: type) type {
    return struct {
        pub fn parse(bytes: []const u8, index: u32) []const u8 {
            const p = combinator.AndThen(left, right);
            const res = p.parse(bytes, index);
            return bytes[res.index..];
        }
    };
}

// .class
const ClassNameParser = RightOnly(DotParser, LabelParser);
// *number
const CountParser = RightOnly(AsterisParser, NumberParser);
// label.class*number
const NodeParser = combinator.AndThen(LabelParser, (combinator.AndThen(combinator.Optional(ClassNameParser), combinator.Optional(CountParser))));
// >node
const SubNodeParser = combinator.AndThen(GreaterParser, NodeParser);
// node > subnode
const ExprParser = combinator.AndThen(NodeParser, combinator.Many(SubNodeParser));

pub fn main() anyerror!void {}

test "test LabelParser" {
    var res = LabelParser.parse("abcd", 0);
    std.debug.print("label {s}\n", .{res});
}

test "test NumberParser" {
    var res = NumberParser.parse("123", 0);
    std.debug.print("digit {s}\n", .{res});
}

test "test ClassNameParser" {
    var res = ClassNameParser.parse(".test", 0);
    std.debug.print("digit {s}\n", .{res});
}
