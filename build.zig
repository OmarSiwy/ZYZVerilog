const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Parser module
    const Parser = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "lib/Parser/lib.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Executable that reads command line
    const exe = b.addExecutable(.{
        .name = "ZYZVerilog",
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("Parser", Parser);
    b.installArtifact(exe);

    // Run Step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Unit tests
    const lib_unit_tests = b.addTest(.{
        .root_source_file = .{ .cwd_relative = "tests/main_test.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib_unit_tests.root_module.addImport("Parser", Parser);

    const run_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // SystemVerilog compliance tests
    const PackagedCompilerInterface = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "lib/TestingInterface/PackagedCompilerInterface.zig" },
        .target = target,
        .optimize = optimize,
    });
    const PackagedCompiler = b.createModule(.{
        .root_source_file = .{ .cwd_relative = "lib/TestingInterface/PackagedCompiler.zig" },
        .target = target,
        .optimize = optimize,
    });
    PackagedCompiler.addImport("PackagedCompilerInterface", PackagedCompilerInterface);

    const sv_compliance_tests = b.addTest(.{
        .root_source_file = .{ .cwd_relative = "tests/sv_compliance_tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    sv_compliance_tests.root_module.addImport("PackagedCompiler", PackagedCompiler);

    const run_sv_tests = b.addRunArtifact(sv_compliance_tests);
    const sv_test_step = b.step("test-sv", "Run SystemVerilog compliance tests");
    sv_test_step.dependOn(&run_sv_tests.step);
}
