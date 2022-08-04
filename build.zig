const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("parser-combinator", "src/main.zig");
    lib.setBuildMode(mode);
    lib.install();

    const main_tests = b.addTest("src/all_test.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    const target = b.standardTargetOptions(.{});

    const emmet_step = b.step("emmet", "Example Emmet");
    const example_emmet = b.addExecutable("emmet", "example/emmet.zig");
    example_emmet.addPackagePath("../src/parser.zig", "src/parser.zig");
    example_emmet.addPackagePath("../src/character.zig", "src/character.zig");
    const cwd = b.build_root;
    const example_emmet_dir = try std.fs.path.join(b.allocator, &[_][]const u8{ cwd, "example" });

    example_emmet.setBuildMode(mode);
    example_emmet.setTarget(target);
    example_emmet.setOutputDir(example_emmet_dir);
    example_emmet.install();

    const emmet_tests = b.addTest("example/emmet.zig");
    emmet_tests.addPackagePath("../src/parser.zig", "src/parser.zig");
    emmet_tests.addPackagePath("../src/character.zig", "src/character.zig");
    const emmet_test_step = b.step("test-emmet", "Run emmet tests");
    emmet_test_step.dependOn(&emmet_tests.step);

    const run_cmd = example_emmet.run();
    run_cmd.step.dependOn(&emmet_tests.step);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    emmet_step.dependOn(&run_cmd.step);
}
