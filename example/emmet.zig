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
const ParseError = Combinators.ParseError;
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

fn listToString(allocator: Allocator, list: ArrayList(u8)) []const u8 {
    _ = allocator;
    var string = allocator.alloc(u8, list.items.len) catch {
        return "";
    };
    std.mem.copy(u8, string[0..], list.items[0..]);
    return string;
}

const LabelParser = Map(ManyOne(Alpha), listToString); // Result([]const u8, []const u8)
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

fn toNumber(allocator: Allocator, str: []const u8) u32 {
    _ = allocator;
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
test "subnode" {
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

fn toEmmetNode(allocator: Allocator, node: NodeParser.OutputType) EmmetNode {
    var label = node.@"0";
    var label_buf = allocator.alloc(u8, label.len) catch {
        return .{};
    };
    std.mem.copy(u8, label_buf, label);
    var classNameAndCounter = node.@"1";
    var className = classNameAndCounter.@"0" orelse "";

    var classname_buf = allocator.alloc(u8, className.len) catch {
        return .{};
    };
    std.mem.copy(u8, classname_buf, className);

    var count = classNameAndCounter.@"1" orelse 1;
    return EmmetNode{
        .count = count,
        .class = classname_buf,
        .label = label_buf,
        .id = null,
    };
}

const ManySubnodes = Many(SubNodeParser);
test "many subnode" {
    const allocator = testing.allocator;
    const word1 = ">ul.root>li.item*12";
    var p1 = ManySubnodes.init(allocator);
    defer p1.deinit();

    var res = try p1.parse(word1);
    const node = res.output.items;

    try testing.expect(std.mem.eql(u8, node[0].label, "ul"));
    try testing.expect(std.mem.eql(u8, node[0].class, "root"));
    try testing.expect(std.mem.eql(u8, node[1].label, "li"));
    try testing.expect(std.mem.eql(u8, node[1].class, "item"));
    try testing.expectEqual(node[1].count, 12);
}

// node > subnode
const ExprParser = And(EmmetNodeParser, ManySubnodes);
test "ExprParser" {
    const allocator = testing.allocator;
    const word1 = "div.root>ul.list>li*12";
    var p1 = ExprParser.init(allocator);
    defer p1.deinit();

    var res1 = try p1.parse(word1);
    var root = res1.output.@"0";
    var children = res1.output.@"1";
    try testing.expectEqual(children.items.len, 2);
    const list = children.items[0];
    const li = children.items[1];
    try testing.expect(std.mem.eql(u8, root.label, "div"));
    try testing.expect(std.mem.eql(u8, root.class, "root"));
    try testing.expectEqual(root.count, 1);
    try testing.expect(std.mem.eql(u8, list.label, "ul"));
    try testing.expect(std.mem.eql(u8, list.class, "list"));
    try testing.expectEqual(list.count, 1);
    try testing.expect(std.mem.eql(u8, li.label, "li"));
    try testing.expect(std.mem.eql(u8, li.class, ""));
    try testing.expectEqual(li.count, 12);
}

const BUF_CAP = 64 * (1 << 10);

const EmmetNode = struct {
    count: u32 = 0,
    label: []const u8 = "",
    class: []const u8 = "",
    id: ?[]const u8 = null,
};

fn serialize(node: EmmetNode, children: []EmmetNode, output_buf_size: usize, output_buf: *[BUF_CAP]u8) anyerror!usize {
    if (children.len == 0) {
        return serializeNode(node, "", output_buf_size, output_buf);
    }
    var children_buf: [BUF_CAP]u8 = undefined;
    var end = try serialize(children[0], children[1..], 0, &children_buf);
    return try serializeNode(node, children_buf[0..end], output_buf_size, output_buf);
}

fn serializeNode(node: EmmetNode, content: []const u8, output_buf_size: usize, output_buf: *[BUF_CAP]u8) anyerror!usize {
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

    if (class.len > 0) {
        const class_str = " class=\"";
        std.mem.copy(u8, element_buf[buf_size..], class_str);
        buf_size += class_str.len;
        const className = class;
        std.mem.copy(u8, element_buf[buf_size..], className);
        buf_size += className.len;
        std.mem.copy(u8, element_buf[buf_size..], "\"");
        buf_size += 1;
    }
    if (id) |idName| {
        _ = try std.fmt.bufPrint(element_buf[buf_size..], "id=\"{s}\"", .{idName});
        buf_size += idName.len + 5;
    }
    _ = try std.fmt.bufPrint(element_buf[buf_size..], ">", .{});
    buf_size += 1;

    _ = try std.fmt.bufPrint(element_buf[buf_size..], "{s}<{s}/>", .{ content, label });
    buf_size += content.len + label.len + 3;

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
    }, "", 0, &test_buf);
    std.debug.print("{s}\n", .{test_buf[0..buf_size]});
}

fn parseStr(allocator: Allocator, input: ExprParser.InputType, buf: *[BUF_CAP]u8) ![]const u8 {
    var parser = ExprParser.init(allocator);
    defer parser.deinit();
    var res = try parser.parse(input);
    var node = res.output.@"0";
    var child_list = res.output.@"1";
    var end = try serialize(node, child_list.items, 0, buf);
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

    var res = try parseStr(a, input, &buf);
    std.debug.print("{s}\n", .{input});
    std.log.info("{s}\n", .{res});
}
