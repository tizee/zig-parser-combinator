const std = @import("std");
const testing = std.testing;
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const combinator = @import("../src/main.zig").combinator;
const ParseResult = combinator.ParseResult;

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
    pub fn parse(bytes: []const u8, index: u32) ParseResult {
        const p = combinator.ManyOne(combinator.Letter);
        return p.parse(bytes, index);
    }
};

const NumberParser = struct {
    pub fn parse(bytes: []const u8, index: u32) ParseResult {
        const p = combinator.ManyOne(combinator.Digit);
        return p.parse(bytes, index);
    }
};

pub fn RightOnly(comptime left: type, comptime right: type) type {
    return struct {
        pub fn parse(bytes: []const u8, index: u32) ParseResult {
            const p = combinator.AndThen(left, right);

            const res1 = left.parse(bytes, index);
            const res = p.parse(bytes, index);
            if (res.state) {
                if (res.value) |value| {
                    return combinator.success([2]u32{ res1.next_index, value[1] }, res.next_index);
                }
            }
            return res;
        }
    };
}

// .class
const ClassNameParser = RightOnly(DotParser, LabelParser);
// #id
const IDParser = RightOnly(SharpParser, LabelParser);
// *number
const CountParser = RightOnly(AsterisParser, NumberParser);
const ClassNameAndIDAndCounter = combinator.AndThen(combinator.Optional(combinator.OrElse(ClassNameParser, IDParser)), combinator.Optional(CountParser));

// label.class*number
const NodeParser = combinator.AndThen(LabelParser, ClassNameAndIDAndCounter);
// >node
const SubNodeParser = combinator.AndThen(GreaterParser, NodeParser);
// node > subnode
const ExprParser = combinator.AndThen(NodeParser, combinator.Many(SubNodeParser));

const BUF_CAP = 64 * (1 << 10);

const EmmetNode = struct {
    label: []const u8,
    classes: []const []const u8,
    id: ?[]const u8,
    count: u32,
};

fn serializeNode(node: EmmetNode, content: []const u8, output_buf_size: usize, output_buf: *[BUF_CAP]u8) !usize {
    var element_buf: [BUF_CAP]u8 = undefined;
    const label = node.label;
    const id = node.id;
    const count = node.count;
    const classes = node.classes;

    var buf_size: usize = 0;
    std.mem.copy(u8, element_buf[buf_size..], "<");
    buf_size += 1;
    std.mem.copy(u8, element_buf[buf_size..], label);
    buf_size += label.len;

    if (node.classes.len > 0) {
        const class_str = " class=\"";
        std.mem.copy(u8, element_buf[buf_size..], class_str);
        buf_size += class_str.len;
        var i: u32 = 0;
        while (i < classes.len) {
            const className = classes[i];
            std.mem.copy(u8, element_buf[buf_size..], className);
            buf_size += className.len;
            if (i != classes.len - 1) {
                std.mem.copy(u8, element_buf[buf_size..], " ");
                buf_size += 1;
            }
            i += 1;
        }
        std.mem.copy(u8, element_buf[buf_size..], "\" ");
        buf_size += 2;
    }
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
        .classes = &.{ "test1", "test2" },
        .id = "root",
        .count = 5,
    }, "hello world", 0, &test_buf);
    std.debug.print("{s}\n", .{test_buf[0..buf_size]});
}

fn parseStr(input: []const u8, buf: *[BUF_CAP]u8) []const u8 {
    var res = ExprParser.parse(input, 0);
    if (res.state) {
        // valid input
        res = NodeParser.parse(input, 0);
    }
    return buf;
}

var a: Allocator = undefined;
pub fn main() anyerror!void {
    var arena = ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    a = arena.allocator();
    var iter = try std.process.argsWithAllocator(a);
    var prog = iter.next();
    defer iter.deinit();

    var input = try (iter.next(a) orelse {
        std.log.err("usage: {s} \"[emmet string]\"", .{prog});
        std.os.exit(1);
    });

    var buf: [BUF_CAP]u8 = undefined;

    std.debug.print("{s}\n", .{input});
    std.log.info("{s}\n", parseStr(input, &buf));
}

test "test LabelParser" {
    const label = "abcd 2345";
    var res = LabelParser.parse(label, 0);
    std.debug.print("{}\n", .{res});
    try testing.expect(res.state);
    if (res.value) |value| {
        std.debug.print("{s}\n", .{label[value[0]..value[1]]});
        try testing.expect(std.mem.eql(u8, label[value[0]..value[1]], "abcd"));
    }
    const label2 = "123";
    res = ClassNameParser.parse(label2, 0);
    std.debug.print("{}\n", .{res});
    try testing.expect(!res.state);
}

test "test NumberParser" {
    const label = "123";
    var res = NumberParser.parse(label, 0);
    std.debug.print("{}\n", .{res});
    try testing.expect(res.state);
    if (res.value) |value| {
        std.debug.print("{s}\n", .{label[value[0]..value[1]]});
        try testing.expect(std.mem.eql(u8, label[value[0]..value[1]], "123"));
    }
    const label2 = "abcd";
    res = ClassNameParser.parse(label2, 0);
    std.debug.print("{}\n", .{res});
    try testing.expect(!res.state);
}

test "test ClassNameParser" {
    const label = ".test";
    var res = ClassNameParser.parse(label, 0);
    std.debug.print("{}\n", .{res});
    try testing.expect(res.state);
    if (res.value) |value| {
        std.debug.print("{s}\n", .{label[value[0]..value[1]]});
        try testing.expect(std.mem.eql(u8, label[value[0]..value[1]], "test"));
    }
    const label2 = ".1234";
    res = ClassNameParser.parse(label2, 0);
    std.debug.print("{}\n", .{res});
    try testing.expect(!res.state);
}

test "test CountParser" {
    const label = "*1234";
    var res = CountParser.parse(label, 0);
    std.debug.print("{}\n", .{res});
    try testing.expect(res.state);
    if (res.value) |value| {
        std.debug.print("{s}\n", .{label[value[0]..value[1]]});
        try testing.expect(std.mem.eql(u8, label[value[0]..value[1]], "1234"));
    }
    const label2 = "*invalid";
    res = CountParser.parse(label2, 0);
    std.debug.print("{}\n", .{res});
    try testing.expect(!res.state);

    const p = combinator.Optional(CountParser);
    res = p.parse(label2, 0);
    std.debug.print("{}\n", .{res});
    try testing.expect(res.state);
}

test "test ClassNameAndCounter" {
    const label = ".className*1234";
    var res = ClassNameAndIDAndCounter.parse(label, 0);
    std.debug.print("{}\n", .{res});
    try testing.expect(res.state);
    if (res.value) |value| {
        std.debug.print("{s}\n", .{label[value[0]..value[1]]});
        try testing.expect(std.mem.eql(u8, label[value[0]..value[1]], label));
    }
}

test "test NodeParser" {
    const label = "hello.className*1234";
    var res = NodeParser.parse(label, 0);
    std.debug.print("{}\n", .{res});
    try testing.expect(res.state);
    if (res.value) |value| {
        std.debug.print("{s}\n", .{label[value[0]..value[1]]});
        try testing.expect(std.mem.eql(u8, label[value[0]..value[1]], label));
    }

    const label2 = ".1234*invalid";
    res = NodeParser.parse(label2, 0);
    std.debug.print("{}\n", .{res});
    try testing.expect(!res.state);

    const label3 = "hello";
    res = NodeParser.parse(label3, 0);
    std.debug.print("{}\n", .{res});
    try testing.expect(res.state);
    if (res.value) |value| {
        std.debug.print("{s}\n", .{label3[value[0]..value[1]]});
        try testing.expect(std.mem.eql(u8, label3[value[0]..value[1]], "hello"));
    }

    const label4 = "hello.classname";
    res = NodeParser.parse(label4, 0);
    std.debug.print("{}\n", .{res});
    try testing.expect(res.state);
    if (res.value) |value| {
        std.debug.print("{s}\n", .{label4[value[0]..value[1]]});
        try testing.expect(std.mem.eql(u8, label4[value[0]..value[1]], label4));
    }

    const label5 = "hello*1234";
    res = NodeParser.parse(label5, 0);
    std.debug.print("{}\n", .{res});
    try testing.expect(res.state);
    if (res.value) |value| {
        std.debug.print("{s}\n", .{label5[value[0]..value[1]]});
        try testing.expect(std.mem.eql(u8, label5[value[0]..value[1]], label5));
    }

    const label6 = "hello*invalid";
    res = NodeParser.parse(label6, 0);
    std.debug.print("{}\n", .{res});
    try testing.expect(res.state);
    if (res.value) |value| {
        std.debug.print("{s}\n", .{label6[value[0]..value[1]]});
        try testing.expect(std.mem.eql(u8, label6[value[0]..value[1]], "hello"));
    }
}

test "test SubNodeParser" {
    const label = ">hello*invalid";
    var res = SubNodeParser.parse(label, 0);
    std.debug.print("{}\n", .{res});
    try testing.expect(res.state);
    if (res.value) |value| {
        std.debug.print("{s}\n", .{label[value[0]..value[1]]});
        try testing.expect(std.mem.eql(u8, label[value[0]..value[1]], ">hello"));
    }

    const label2 = ">hello.class*1234>";
    res = SubNodeParser.parse(label2, 0);
    std.debug.print("{}\n", .{res});
    try testing.expect(res.state);
    if (res.value) |value| {
        std.debug.print("{s}\n", .{label2[value[0]..value[1]]});
        try testing.expect(std.mem.eql(u8, label2[value[0]..value[1]], ">hello.class*1234"));
    }
}

test "test ExprParser" {
    const label = "root.index*123>hello*invalid";
    var res = ExprParser.parse(label, 0);
    std.debug.print("{}\n", .{res});
    try testing.expect(res.state);
    if (res.value) |value| {
        std.debug.print("{s}\n", .{label[value[0]..value[1]]});
        try testing.expect(std.mem.eql(u8, label[value[0]..value[1]], "root.index*123>hello"));
    }

    const label2 = "root>hello.class*1234>sub";
    res = ExprParser.parse(label2, 0);
    std.debug.print("{}\n", .{res});
    try testing.expect(res.state);
    if (res.value) |value| {
        std.debug.print("{s}\n", .{label2[value[0]..value[1]]});
        try testing.expect(std.mem.eql(u8, label2[value[0]..value[1]], "root>hello.class*1234>sub"));
    }
}
