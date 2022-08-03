const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const ArrayHashMap = std.ArrayHashMap;

const meta = @import("meta.zig");
const Result = meta.Result;

const testing = std.testing;
const debug = std.debug;
const assert = debug.assert;

pub const ParseError = error{ NotEnoughInput, InvalidInput, ArrayListFailure };

// Generic Parser Interface
pub fn Parser(comptime P: type) type {
    return struct {
        const Self = @This();
        pub const InputType = P.InputType;
        pub const OutputType = P.OutputType;
        pub const ResultType = P.ResultType;

        inner: P,

        pub fn parse(self: *Self, input: P.InputType) ParseError!ResultType {
            return self.inner.parse(input);
        }

        pub fn init(allocator: ?Allocator) Self {
            return Self{ .inner = P.init(allocator) };
        }

        pub fn deinit(self: *Self) void {
            self.inner.deinit();
        }

        // return a andThen parser
        pub fn andThen(G: type) type {
            return AndThen(P, G);
        }

        // return a Map parser
        pub fn map(transformFn: anytype) type {
            return Map(P, transformFn);
        }

        // return a Map parser
        pub fn andParser(P2: type) type {
            return And(P, P2);
        }

        // return a Map parser
        pub fn orParser(P2: type) type {
            return Or(P, P2);
        }
    };
}

// omit the first parser's output
pub fn RightOnly(comptime P1: type, comptime P2: type) type {
    return Parser(RightOnlyParser(P1, P2));
}

fn RightOnlyParser(comptime P1: type, comptime P2: type) type {
    comptime {
        meta.assertSameType("RightOnlyParser P1 InputType should be the same as the InputType of P2", P1.InputType, P2.InputType);
    }
    return struct {
        const Self = @This();
        pub const InputType = P1.InputType;
        pub const OutputType = P2.OutputType;
        pub const ResultType = Result(InputType, OutputType);

        f: P1,
        g: P2,

        pub fn deinit(self: *Self) void {
            self.f.deinit();
            self.g.deinit();
        }

        pub fn init(allocator: ?Allocator) Self {
            return Self{
                .f = P1.init(allocator),
                .g = P2.init(allocator),
            };
        }

        pub fn parse(self: *Self, input: InputType) ParseError!ResultType {
            var res = try self.f.parse(input);
            var res2 = try self.g.parse(res.input);
            return ResultType{ .input = res2.input, .output = res2.output };
        }
    };
}

// Generic AndThen Interface
pub fn AndThen(comptime P1: type, comptime P2: type) type {
    return Parser(AndThenParser(P1, P2));
}

fn AndThenParser(comptime P1: type, comptime P2: type) type {
    comptime {
        meta.assertSameType("AndThenParser P1 OutputType should be the same as the InputType of P2", P1.OutputType, P2.InputType);
    }
    return struct {
        const Self = @This();
        pub const InputType = P1.InputType;
        pub const OutputType = P2.OutputType;
        pub const ResultType = Result(InputType, OutputType);

        f: P1,
        g: P2,

        pub fn deinit(self: *Self) void {
            self.f.deinit();
            self.g.deinit();
        }

        pub fn init(allocator: ?Allocator) Self {
            return Self{
                .f = P1.init(allocator),
                .g = P2.init(allocator),
            };
        }

        pub fn parse(self: *Self, input: InputType) ParseError!ResultType {
            var res = try self.f.parse(input);
            var res2 = try self.g.parse(res.output);
            return ResultType{ .input = res.input, .output = res2.output };
        }
    };
}

pub fn Map(comptime P: type, transformFn: anytype) type {
    return Parser(MapParser(P, transformFn));
}

fn MapParser(comptime P: type, transformFn: anytype) type {
    comptime {
        meta.assertFn("MapParser transformFn", transformFn);
    }
    return struct {
        const Self = @This();
        pub const InputType = P.InputType;
        pub const OutputType = meta.ReturnType(transformFn);
        pub const ResultType = Result(InputType, OutputType);

        inner: P,

        pub fn deinit(self: *Self) void {
            self.inner.deinit();
        }

        pub fn init(allocator: ?Allocator) Self {
            return Self{ .inner = P.init(allocator) };
        }

        pub fn parse(self: *Self, input: InputType) ParseError!ResultType {
            var res = try self.inner.parse(input);
            return ResultType{ .input = res.input, .output = transformFn(res.output) };
        }
    };
}

pub fn Or(comptime P1: type, comptime P2: type) type {
    return Parser(OrParser(P1, P2));
}

fn OrParser(comptime P1: type, P2: type) type {
    comptime {
        meta.assertSameType("OrParser P1 InputType should be the same as the InputType of P2", P1.InputType, P2.InputType);
        meta.assertSameType("OrParser P1 OutputType should be the same as the OutputType of P2", P1.OutputType, P2.OutputType);
    }
    return struct {
        const Self = @This();
        pub const InputType = P1.InputType;
        pub const OutputType = P1.OutputType;
        pub const ResultType = Result(InputType, OutputType);

        f: P1,
        g: P2,

        pub fn init(allocator: ?Allocator) Self {
            return Self{ .f = P1.init(allocator), .g = P2.init(allocator) };
        }

        pub fn deinit(self: *Self) void {
            self.f.deinit();
            self.g.deinit();
        }

        pub fn parse(self: *Self, input: InputType) ParseError!ResultType {
            var res: ?ResultType = self.f.parse(input) catch null;
            if (res == null) {
                return self.g.parse(input);
            }
            return res.?;
        }
    };
}

pub fn And(comptime P1: type, comptime P2: type) type {
    return Parser(AndParser(P1, P2));
}

fn AndParser(comptime P1: type, P2: type) type {
    comptime {
        meta.assertSameType("AndParser P1 InputType should be the same as the InputType of P2", P1.InputType, P2.InputType);
    }
    return struct {
        const Self = @This();
        pub const InputType = P1.InputType;
        // tuple
        pub const OutputType = struct { @"0": P1.OutputType, @"1": P2.OutputType };
        pub const ResultType = Result(InputType, OutputType);

        f: P1,
        g: P2,

        pub fn deinit(self: *Self) void {
            self.f.deinit();
            self.g.deinit();
        }

        pub fn init(allocator: ?Allocator) Self {
            return Self{ .f = P1.init(allocator), .g = P2.init(allocator) };
        }

        pub fn parse(self: *Self, input: InputType) ParseError!ResultType {
            var res1 = try self.f.parse(input);
            var res2 = try self.g.parse(res1.input);
            return ResultType{ .input = res2.input, .output = .{
                .@"0" = res1.output,
                .@"1" = res2.output,
            } };
        }
    };
}

pub fn Many(comptime P: type) type {
    return Parser(ManyParser(P));
}

fn ManyParser(comptime P: type) type {
    return struct {
        const Self = @This();
        pub const InputType = P.InputType;
        pub const OutputType = *ArrayList(P.OutputType);
        const InnerResultType = P.ResultType;
        pub const ResultType = Result(InputType, OutputType);

        inner: P,
        allocator: Allocator,
        result: ArrayList(P.OutputType),

        pub fn init(allocator: ?Allocator) Self {
            return Self{ .inner = P.init(allocator), .allocator = allocator.?, .result = ArrayList(P.OutputType).init(allocator.?) };
        }

        pub fn deinit(self: *Self) void {
            self.result.deinit();
        }

        fn clear(self: *Self) void {
            while (self.result.popOrNull()) |_| {}
        }

        pub fn parse(self: *Self, input: InputType) ParseError!ResultType {
            self.clear();
            var list: *ArrayList(P.OutputType) = &self.result;
            var i = input;
            while (true) {
                var another = i;
                var res: ?InnerResultType = self.inner.parse(another) catch |e|
                    switch (e) {
                    ParseError.NotEnoughInput => {
                        break;
                    },
                    else => null,
                };
                if (res == null) {
                    return ParseError.InvalidInput;
                }
                i = res.?.input;
                list.*.append(res.?.output) catch {
                    return ParseError.ArrayListFailure;
                };
            }
            return ResultType{
                .input = i,
                .output = list,
            };
        }
    };
}

pub fn ManyOne(comptime P: type) type {
    return Parser(ManyOneParser(P));
}

fn ManyOneParser(comptime P: type) type {
    return struct {
        const Self = @This();
        pub const InputType = P.InputType;
        pub const OutputType = *ArrayList(P.OutputType);
        const InnerResultType = P.ResultType;
        pub const ResultType = Result(InputType, OutputType);

        inner: P,
        allocator: Allocator,
        result: ArrayList(P.OutputType),

        pub fn init(allocator: ?Allocator) Self {
            return Self{ .inner = P.init(allocator), .allocator = allocator.?, .result = ArrayList(P.OutputType).init(allocator.?) };
        }

        pub fn deinit(self: *Self) void {
            self.result.deinit();
        }

        fn clear(self: *Self) void {
            while (self.result.popOrNull()) |_| {}
        }

        pub fn parse(self: *Self, input: InputType) ParseError!ResultType {
            self.clear();
            var list: *ArrayList(P.OutputType) = &self.result;
            var i = input;
            var i_clone = input;
            var res: ?InnerResultType = self.inner.parse(i_clone) catch |e|
                switch (e) {
                ParseError.NotEnoughInput => {
                    return ParseError.NotEnoughInput;
                },
                else => null,
            };
            if (res == null) {
                return ParseError.InvalidInput;
            }
            list.*.append(res.?.output) catch {
                return ParseError.ArrayListFailure;
            };
            i = res.?.input;
            while (true) {
                var another = i;
                res = self.inner.parse(another) catch {
                    break;
                };
                i = res.?.input;
                list.*.append(res.?.output) catch {
                    return ParseError.ArrayListFailure;
                };
            }
            return ResultType{
                .input = i,
                .output = list,
            };
        }
    };
}

/// Optional parser return null when failed
pub fn Optional(comptime P: type) type {
    return Parser(OptionalParser(P));
}

fn OptionalParser(comptime P: type) type {
    return struct {
        const Self = @This();
        pub const InputType = P.InputType;
        pub const OutputType = ?P.OutputType;
        pub const ResultType = Result(InputType, OutputType);

        inner: P,

        pub fn init(allocator: ?Allocator) Self {
            return Self{ .inner = P.init(allocator) };
        }

        pub fn deinit(self: *Self) void {
            self.inner.deinit();
        }

        pub fn parse(self: *Self, input: InputType) ParseError!ResultType {
            var res = self.inner.parse(input) catch {
                return ResultType{
                    .input = input,
                    .output = null,
                };
            };
            return ResultType{
                .input = res.input,
                .output = res.output,
            };
        }
    };
}
