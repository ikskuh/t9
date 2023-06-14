const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const demo = b.addExecutable("t9-demo", "src/main.zig");
    demo.setBuildMode(mode);
    demo.linkLibC(); // faster allocation
    demo.install();

    const run_demo = demo.run();

    const run_step = b.step("run", "Runs the demo");
    run_step.dependOn(&run_demo.step);

    const main_tests = b.addTest("src/t9.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
