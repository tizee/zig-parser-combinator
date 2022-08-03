const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const CharacterParser = @import("../src/character.zig");
const SatisfyParser = CharacterParser.SatisfyParser;
const Digit = CharacterParser.Digit;
const Alpha = CharacterParser.Alpha;

const Combinators = @import("../src/parser.zig");
const Parser = Combinators.Parser;
const AndThen = Combinators.AndThen;
const Or = Combinators.Or;
const And = Combinators.And;
const RightOnly = Combinators.RightOnly;
const ManyOne = Combinators.ManyOne;
const Many = Combinators.Many;
const Optional = Combinators.Optional;
const Map = Combinators.Map;

// global allocator
var a: Allocator = undefined;

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

const DotParser = Parser(SatisfyParser(isDot));
const AsterisParser = Parser(SatisfyParser(isAsterisk));
const GreaterParser = Parser(SatisfyParser(isGreater));
const SharpParser = Parser(SatisfyParser(isSharp));

fn listToString(list: *ArrayList(u8)) []const u8 {
    return list.*.items;
}

const LabelParser = Map(ManyOne(Alpha), listToString); // Result(const []u8, const []u8)
const NumberParser = Map(ManyOne(Digit), listToString);

test "label and number" {
    const allocator = testing.allocator;
    const word1 = "abcd";
    const word2 = "1234";
    var p1 = LabelParser.init(allocator);
    defer p1.deinit();
    var p2 = NumberParser.init(allocator);
    defer p2.deinit();

    var res1 = try p1.parse(word1);
    var res2 = try p2.parse(word2);
    try testing.expect(std.mem.eql(u8, res1.output, word1));
    try testing.expect(std.mem.eql(u8, res2.output, word2));
}

// .class
const ClassNameParser = RightOnly(DotParser, LabelParser);
test "ClassNameParser" {
    const allocator = testing.allocator;
    const word1 = ".abcd";
    var p1 = ClassNameParser.init(allocator);
    defer p1.deinit();

    var res1 = try p1.parse(word1);
    try testing.expect(std.mem.eql(u8, res1.output, "abcd"));
}

// #id
const IDParser = RightOnly(SharpParser, LabelParser);
test "IDParser" {
    const allocator = testing.allocator;
    const word1 = "#abcd";
    var p1 = IDParser.init(allocator);
    defer p1.deinit();

    var res1 = try p1.parse(word1);
    try testing.expect(std.mem.eql(u8, res1.output, "abcd"));
}

fn toNumber(str: []const u8) u32 {
    var num: u32 = 0;
    var i: usize = 0;
    while (i < str.len - 1) : (i += 1) {
        num += str[i] - '0';
        num *= 10;
    }
    num += str[i] - '0';
    return num;
}
// *number
const CountParser = RightOnly(AsterisParser, Map(NumberParser, toNumber));
test "number" {
    const allocator = testing.allocator;
    const word1 = "*1234";
    var p1 = CountParser.init(allocator);
    defer p1.deinit();

    var res1 = try p1.parse(word1);
    debug.print("{}", .{res1});
    try testing.expectEqual(res1.output, 1234);
}
const ClassNameAndCounter = And(Optional(ClassNameParser), Optional(CountParser));
test "class and counter" {
    const allocator = testing.allocator;
    const word1 = ".root*1234";
    var p1 = ClassNameAndCounter.init(allocator);
    defer p1.deinit();

    var res1 = try p1.parse(word1);
    try testing.expect(std.mem.eql(u8, res1.output.@"0".?, "root"));
    try testing.expectEqual(res1.output.@"1".?, 1234);
}

// label.class*number
const NodeParser = And(LabelParser, ClassNameAndCounter);
test "node" {
    const allocator = testing.allocator;
    const word1 = "div.root*1234";
    var p1 = NodeParser.init(allocator);
    defer p1.deinit();

    var res1 = try p1.parse(word1);
    const label = res1.output.@"0";
    const classAndCounter = res1.output.@"1";
    try testing.expect(std.mem.eql(u8, label, "div"));
    try testing.expect(std.mem.eql(u8, classAndCounter.@"0".?, "root"));
    try testing.expectEqual(classAndCounter.@"1".?, 1234);
}

const EmmetNodeParser = Map(NodeParser, toEmmetNode);
test "emmet node" {
    const allocator = testing.allocator;
    const word1 = "div.root*1234";
    var p1 = EmmetNodeParser.init(allocator);
    defer p1.deinit();

    var res1 = try p1.parse(word1);
    const node = res1.output;
    try testing.expect(std.mem.eql(u8, node.label, "div"));
    try testing.expect(std.mem.eql(u8, node.class, "root"));
    try testing.expectEqual(node.count, 1234);
}

// >node
const SubNodeParser = RightOnly(GreaterParser, EmmetNodeParser);
test "node" {
    const allocator = testing.allocator;
    const word1 = ">div.root*1234";
    var p1 = SubNodeParser.init(allocator);
    defer p1.deinit();

    var res1 = try p1.parse(word1);
    const node = res1.output;
    try testing.expect(std.mem.eql(u8, node.label, "div"));
    try testing.expect(std.mem.eql(u8, node.class, "root"));
    try testing.expectEqual(node.count, 1234);
}

fn toEmmetNode(node: NodeParser.OutputType) EmmetNode {
    const label = node.@"0";
    const classNameAndCounter = node.@"1";
    const className = classNameAndCounter.@"0" orelse "";
    const count = classNameAndCounter.@"1" orelse 1;
    return EmmetNode{
        .label = label,
        .class = className,
        .id = null,
        .count = count,
    };
}

// node > subnode
const ExprParser = And(EmmetNodeParser, Many(SubNodeParser));
test "ExprParser" {
    const allocator = testing.allocator;
    const word1 = "div>div.root*1234";
    var p1 = ExprParser.init(allocator);
    defer p1.deinit();

    var res1 = try p1.parse(word1);
    const root = res1.output.@"0";
    const node_list = res1.output.@"1";
    const child = node_list.items[0];
    try testing.expect(std.mem.eql(u8, root.label, "div"));
    try testing.expectEqual(root.count, 1);
    try testing.expect(std.mem.eql(u8, child.label, "div"));
    try testing.expect(std.mem.eql(u8, child.class, "root"));
    try testing.expectEqual(child.count, 1234);
}

const BUF_CAP = 64 * (1 << 10);

const EmmetNode = struct {
    label: []const u8,
    class: []const u8,
    id: ?[]const u8,
    count: u32,
};

fn serializeNode(node: EmmetNode, content: []const u8, output_buf_size: usize, output_buf: *[BUF_CAP]u8) !usize {
    var element_buf: [BUF_CAP]u8 = undefined;
    const label = node.label;
    const id = node.id;
    const count = node.count;
    const class = node.class;
    if (count == 0) return output_buf_size;

    var buf_size: usize = 0;
    std.mem.copy(u8, element_buf[buf_size..], "<");
    buf_size += 1;
    std.mem.copy(u8, element_buf[buf_size..], label);
    buf_size += label.len;

    const class_str = " class=\"";
    std.mem.copy(u8, element_buf[buf_size..], class_str);
    buf_size += class_str.len;
    const className = class;
    std.mem.copy(u8, element_buf[buf_size..], className);
    buf_size += className.len;
    std.mem.copy(u8, element_buf[buf_size..], "\" ");
    buf_size += 2;
    if (id) |idName| {
        _ = try std.fmt.bufPrint(element_buf[buf_size..], "id=\"{s}\"", .{idName});
        buf_size += idName.len + 5;
    }
    _ = try std.fmt.bufPrint(element_buf[buf_size..], ">{s}<{s}/>", .{ content, label });
    buf_size += content.len + label.len + 4;

    var i: u32 = 0;
    var output_size = output_buf_size;
    while (i < count and output_size + buf_size < output_buf.len) {
        std.mem.copy(u8, output_buf[output_size..], element_buf[0..buf_size]);
        output_size += buf_size;
        i += 1;
    }
    // +1 for the sentinel
    return output_size;
}

test "test serializeNode" {
    var test_buf: [BUF_CAP]u8 = undefined;
    const buf_size = try serializeNode(EmmetNode{
        .label = "div",
        .class = "test1",
        .id = "root",
        .count = 5,
    }, "hello world", 0, &test_buf);
    std.debug.print("{s}\n", .{test_buf[0..buf_size]});
}

fn parseStr(input: ExprParser.InputType, buf: *[BUF_CAP]u8) ![]const u8 {
    var parser = ExprParser.init(a);
    defer parser.deinit();
    var res = try parser.parse(input);
    var node = res.output.@"0";
    debug.print("{}", .{node});
    var child_list = res.output.@"1";
    var end = try serializeNode(node, "", 0, buf);
    for (child_list.*.items) |child| {
        end = try serializeNode(child, "", end, buf);
    }
    return buf[0..end];
}

pub fn main() anyerror!void {
    var arena = ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    a = arena.allocator();
    var iter = try std.process.argsWithAllocator(a);
    var prog = iter.next();
    defer iter.deinit();

    var input = iter.next() orelse {
        std.log.err("usage: {s} \"[emmet string]\"", .{prog.?});
        std.os.exit(1);
    };

    var buf: [BUF_CAP]u8 = undefined;

    var res = try parseStr(input, &buf);
    std.debug.print("{s}\n", .{input});
    std.log.info("{s}\n", .{res});
}
