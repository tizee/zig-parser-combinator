# parser-combinator-zig

A simple Zig parser combinator library.

```shell
$ zig version
0.10.0-dev.3340+c6f5832bb
```

## Examples

- An simple Emmet parser

```
zig build emmet
./example/emmet "div.root>ul>list>li.5"
```

## Acknowledgment

This project was inspired from following projects:

- https://github.com/haskell/parsec
- https://github.com/Geal/nom
- https://github.com/yetone/parsec.js
- https://github.com/longlongh4/demo_parser_combinator
