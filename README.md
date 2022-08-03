# parser-combinator-zig

A simple Zig parser combinator library.

```shell
$ zig version
0.10.0-dev.3340+c6f5832bb
```

## Usage

```
const std = @import("std");
const parserCombinator = @import("parser-combinator");

const Many = parserCombinator.Many;
const Digit = parserCombinator.Digit;
const Alpha = parserCombinator.Alpha;

pub fn main() void {
  const Parser = AndThen(Many(Alpha),Many(digit()));
  const str:[]const u8 = "abcd1234";
  var parser = Parser.init(allocator);
  var res = parser.parse(str);
  // Result(ArrayList(Result(ArrayList(Result(u8, []const u8)), []const u8),Reulst(ArrayList(Result(u8, []const u8), []const u8))), []const u8)))
}

```

## Examples

- json parser

```
make json
```

- Emmet parser

```
make emmet
```

## Acknowledgment

This project was inspired from following projects:

- https://github.com/haskell/parsec
- https://github.com/Geal/nom
- https://github.com/yetone/parsec.js
- https://github.com/longlongh4/demo_parser_combinator
