const std = @import("std");
const testing = std.testing;
const fs = std.fs;
const mem = std.mem;
const print = std.debug.print;

// Import the shared compiler interface
const PackagedCompiler = @import("PackagedCompiler").YourSVParser;

const SVInterface = @import("PackagedCompiler").SVInterface;
const SVCompilerInterface = SVInterface.SVCompilerInterface;
const createCompilerInterface = SVInterface.createCompilerInterface;
const CompileResult = SVInterface.CompileResult;

// Import your PackagedCompiler

pub const SVTestResult = enum {
    pass,
    fail,
    skip,
    error_compile,
    error_runtime,
};

pub const SVTestCase = struct {
    name: []const u8,
    file_path: []const u8,
    description: []const u8,
    tags: []const []const u8,
    should_fail: bool = false,
    should_fail_reason: ?[]const u8 = null,

    const Self = @This();

    pub fn run(self: Self, allocator: mem.Allocator, compiler: SVCompilerInterface) !SVTestResult {
        // Read the test file
        _ = compiler;
        const file_content = fs.cwd().readFileAlloc(allocator, self.file_path, 1024 * 1024) catch |err| {
            print("Failed to read test file {s}: {}\n", .{ self.file_path, err });
            return SVTestResult.error_compile;
        };
        defer allocator.free(file_content);

        // BYPASS THE BROKEN INTERFACE - create a fresh compiler instance for each test
        var fresh_compiler = PackagedCompiler.init(allocator);
        defer fresh_compiler.deinit();

        // Call compileAdvanced directly
        const compile_result = fresh_compiler.compileAdvanced(allocator, file_content) catch |err| {
            if (self.should_fail) {
                // Expected to fail - this is a pass
                return SVTestResult.pass;
            } else {
                print("Compile failed for {s}: {}\n", .{ self.name, err });
                return SVTestResult.fail;
            }
        };

        // If compilation succeeded but should have failed
        if (self.should_fail) {
            print("Test {s} should have failed but passed\n", .{self.name});
            return SVTestResult.fail;
        }

        // Compilation succeeded and was expected to succeed
        // Clean up the result
        var mutable_result = compile_result;
        mutable_result.deinit(allocator);

        return SVTestResult.pass;
    }
};

pub const SVTestSuite = struct {
    allocator: mem.Allocator,
    test_cases: std.ArrayList(SVTestCase),
    compiler_instance: PackagedCompiler, // Store the actual compiler
    compiler: SVCompilerInterface, // Store the interface

    const Self = @This();

    pub fn init(allocator: mem.Allocator, compiler_instance: PackagedCompiler) Self {
        const stored_compiler = compiler_instance; // Copy the instance
        // Create interface AFTER storing the compiler, using the stored instance's address
        var result = Self{
            .allocator = allocator,
            .test_cases = std.ArrayList(SVTestCase).init(allocator),
            .compiler_instance = stored_compiler,
            .compiler = undefined, // Will be set below
        };

        // Now create the interface using the address of the stored compiler
        result.compiler = result.compiler_instance.createInterface();

        return result;
    }

    pub fn deinit(self: *Self) void {
        // Clean up allocated test case data
        for (self.test_cases.items) |test_case| {
            self.allocator.free(test_case.name);
            self.allocator.free(test_case.file_path);
            if (test_case.description.len > 0) {
                self.allocator.free(test_case.description);
            }
            if (test_case.should_fail_reason) |reason| {
                self.allocator.free(reason);
            }
            for (test_case.tags) |tag| {
                self.allocator.free(tag);
            }
            if (test_case.tags.len > 0) {
                self.allocator.free(test_case.tags);
            }
        }

        self.test_cases.deinit();
        self.compiler_instance.deinit(); // Clean up the stored compiler
    }

    pub fn loadTestsFromDirectory(self: *Self, test_dir: []const u8) !void {
        var dir = fs.cwd().openDir(test_dir, .{ .iterate = true }) catch {
            print("Failed to open directory {s}\n", .{test_dir});
            return;
        };

        var walker = try dir.walk(self.allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!mem.endsWith(u8, entry.basename, ".sv")) continue;

            // Create full path
            const full_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ test_dir, entry.path });
            defer self.allocator.free(full_path);

            // Parse test metadata from file
            const test_case = try self.parseTestMetadata(full_path);
            try self.test_cases.append(test_case);
        }

        print("Loaded {} test cases from {s}\n", .{ self.test_cases.items.len, test_dir });
    }

    pub fn loadAllAvailableTests(self: *Self) !void {
        // List of all available chapters based on your directory listing
        const chapters = [_][]const u8{ "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15", "16", "18", "20", "21", "22", "23", "24", "25", "26" };

        print("Loading tests from all available chapters...\n", .{});

        for (chapters) |chapter| {
            const chapter_dir = try std.fmt.allocPrint(self.allocator, "sv-tests/tests/chapter-{s}", .{chapter});
            defer self.allocator.free(chapter_dir);

            // Check if directory exists before trying to load
            if (fs.cwd().openDir(chapter_dir, .{})) |_| {
                try self.loadTestsFromDirectory(chapter_dir);
            } else |_| {
                print("Skipping chapter {s} (directory not found)\n", .{chapter});
            }
        }

        // Also load generic tests if they exist
        if (fs.cwd().openDir("sv-tests/tests/generic", .{})) |_| {
            try self.loadTestsFromDirectory("sv-tests/tests/generic");
        } else |_| {
            print("No generic tests found\n", .{});
        }

        print("Total tests loaded: {}\n", .{self.test_cases.items.len});
    }

    fn parseTestMetadata(self: *Self, file_path: []const u8) !SVTestCase {
        const file_content = try fs.cwd().readFileAlloc(self.allocator, file_path, 1024 * 1024);
        defer self.allocator.free(file_content);

        var test_case = SVTestCase{
            .name = try self.allocator.dupe(u8, fs.path.stem(file_path)),
            .file_path = try self.allocator.dupe(u8, file_path),
            .description = try self.allocator.dupe(u8, ""),
            .tags = &[_][]const u8{},
        };

        // Parse metadata comments from the file
        var lines = mem.splitSequence(u8, file_content, "\n");
        while (lines.next()) |line| {
            const trimmed = mem.trim(u8, line, " \t\r\n");

            // Look for metadata block starting with /*
            if (mem.startsWith(u8, trimmed, "/*") and mem.indexOf(u8, trimmed, ":name:") != null) {
                // Parse test metadata block
                while (lines.next()) |meta_line| {
                    const meta_trimmed = mem.trim(u8, meta_line, " \t\r\n");
                    if (mem.indexOf(u8, meta_trimmed, "*/")) |_| break;

                    if (mem.startsWith(u8, meta_trimmed, ":description:")) {
                        const desc_start = mem.indexOf(u8, meta_trimmed, ":description:").? + ":description:".len;
                        self.allocator.free(test_case.description);
                        test_case.description = try self.allocator.dupe(u8, mem.trim(u8, meta_trimmed[desc_start..], " \t"));
                    }

                    if (mem.startsWith(u8, meta_trimmed, ":should_fail_because:")) {
                        test_case.should_fail = true;
                        const reason_start = mem.indexOf(u8, meta_trimmed, ":should_fail_because:").? + ":should_fail_because:".len;
                        test_case.should_fail_reason = try self.allocator.dupe(u8, mem.trim(u8, meta_trimmed[reason_start..], " \t"));
                    }

                    if (mem.startsWith(u8, meta_trimmed, ":tags:")) {
                        const tags_start = mem.indexOf(u8, meta_trimmed, ":tags:").? + ":tags:".len;
                        const tags_str = mem.trim(u8, meta_trimmed[tags_start..], " \t");
                        var tag_list = std.ArrayList([]const u8).init(self.allocator);
                        defer tag_list.deinit();

                        var tag_iter = mem.splitSequence(u8, tags_str, " ");
                        while (tag_iter.next()) |tag| {
                            const trimmed_tag = mem.trim(u8, tag, " \t");
                            if (trimmed_tag.len > 0) {
                                try tag_list.append(try self.allocator.dupe(u8, trimmed_tag));
                            }
                        }

                        test_case.tags = try tag_list.toOwnedSlice();
                    }
                }
                break;
            }
        }

        return test_case;
    }

    pub fn runAllTests(self: *Self) !void {
        var passed: u32 = 0;
        var failed: u32 = 0;
        var skipped: u32 = 0;
        var errors: u32 = 0;

        print("Running {} SystemVerilog compliance tests...\n", .{self.test_cases.items.len});

        // Start performance timer
        const start_time = std.time.nanoTimestamp();
        var total_compile_time: u64 = 0;

        for (self.test_cases.items) |test_case| {
            // Measure individual test compilation time
            const test_start = std.time.nanoTimestamp();

            const result = test_case.run(self.allocator, self.compiler) catch |err| {
                print("Error running test {s}: {}\n", .{ test_case.name, err });
                errors += 1;
                continue;
            };

            const test_end = std.time.nanoTimestamp();
            const test_duration = test_end - test_start;
            total_compile_time += @intCast(test_duration);

            switch (result) {
                .pass => {
                    passed += 1;
                    // Only print passes in verbose mode to reduce output
                    // print("PASS: {s}\n", .{test_case.name});
                },
                .fail => {
                    failed += 1;
                    print("FAIL: {s} - {s}\n", .{ test_case.name, test_case.description });
                },
                .skip => {
                    skipped += 1;
                    print("SKIP: {s}\n", .{test_case.name});
                },
                .error_compile, .error_runtime => {
                    errors += 1;
                    print("ERROR: {s}\n", .{test_case.name});
                },
            }
        }

        const end_time = std.time.nanoTimestamp();
        const total_duration = end_time - start_time;

        print("\n=== PERFORMANCE RESULTS ===\n", .{});
        print("Total execution time: {d:.2} ms\n", .{@as(f64, @floatFromInt(total_duration)) / 1_000_000.0});
        print("Total compilation time: {d:.2} ms\n", .{@as(f64, @floatFromInt(total_compile_time)) / 1_000_000.0});
        print("Average per test: {d:.2} ms\n", .{@as(f64, @floatFromInt(total_compile_time)) / @as(f64, @floatFromInt(self.test_cases.items.len)) / 1_000_000.0});
        print("Tests per second: {d:.0}\n", .{@as(f64, @floatFromInt(self.test_cases.items.len)) / (@as(f64, @floatFromInt(total_duration)) / 1_000_000_000.0)});

        print("\n=== FINAL RESULTS ===\n", .{});
        print("Total: {} tests\n", .{self.test_cases.items.len});
        print("Passed: {} ({}%)\n", .{ passed, if (self.test_cases.items.len > 0) passed * 100 / @as(u32, @intCast(self.test_cases.items.len)) else 0 });
        print("Failed: {} ({}%)\n", .{ failed, if (self.test_cases.items.len > 0) failed * 100 / @as(u32, @intCast(self.test_cases.items.len)) else 0 });
        print("Skipped: {}\n", .{skipped});
        print("Errors: {}\n", .{errors});

        if (failed > 0 or errors > 0) {
            return error.TestsFailed;
        }
    }

    pub fn runTestsByTag(self: *Self, tag: []const u8) !void {
        print("Running SystemVerilog compliance tests for tag: {s}\n", .{tag});

        var count: u32 = 0;
        var passed: u32 = 0;
        var failed: u32 = 0;

        for (self.test_cases.items) |test_case| {
            // Check if test case has the specified tag
            for (test_case.tags) |test_tag| {
                if (mem.eql(u8, test_tag, tag)) {
                    const result = try test_case.run(self.allocator, self.compiler);
                    count += 1;
                    switch (result) {
                        .pass => {
                            passed += 1;
                            print("PASS: {s}\n", .{test_case.name});
                        },
                        .fail => {
                            failed += 1;
                            print("FAIL: {s}\n", .{test_case.name});
                        },
                        .skip => print("SKIP: {s}\n", .{test_case.name}),
                        .error_compile, .error_runtime => print("ERROR: {s}\n", .{test_case.name}),
                    }
                    break;
                }
            }
        }

        if (count == 0) {
            print("No tests found with tag: {s}\n", .{tag});
        } else {
            print("Tag {s} results: {}/{} passed\n", .{ tag, passed, count });
        }
    }

    pub fn runTestsByChapter(self: *Self, chapter: []const u8) !void {
        const chapter_dir = try std.fmt.allocPrint(self.allocator, "sv-tests/tests/chapter-{s}", .{chapter});
        defer self.allocator.free(chapter_dir);

        // Clear existing tests and load chapter-specific tests
        for (self.test_cases.items) |test_case| {
            self.allocator.free(test_case.name);
            self.allocator.free(test_case.file_path);
            if (test_case.description.len > 0) {
                self.allocator.free(test_case.description);
            }
            if (test_case.should_fail_reason) |reason| {
                self.allocator.free(reason);
            }
        }
        self.test_cases.clearAndFree();

        try self.loadTestsFromDirectory(chapter_dir);
        try self.runAllTests();
    }

    pub fn printTestStatistics(self: *Self) void {
        var chapter_stats = std.HashMap([]const u8, u32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        defer chapter_stats.deinit();

        print("\n=== TEST STATISTICS ===\n", .{});

        for (self.test_cases.items) |test_case| {
            // Extract chapter from file path
            if (mem.indexOf(u8, test_case.file_path, "chapter-")) |start| {
                const chapter_start = start + "chapter-".len;
                if (mem.indexOf(u8, test_case.file_path[chapter_start..], "/")) |end| {
                    const chapter = test_case.file_path[chapter_start .. chapter_start + end];
                    const result = chapter_stats.getOrPut(chapter) catch continue;
                    if (!result.found_existing) {
                        result.value_ptr.* = 1;
                    } else {
                        result.value_ptr.* += 1;
                    }
                }
            }
        }

        var iterator = chapter_stats.iterator();
        while (iterator.next()) |entry| {
            print("Chapter {s}: {} tests\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }
};

// Helper function to create test suite with your compiler
fn createTestSuite(allocator: mem.Allocator) !SVTestSuite {
    // Debug: Verify allocator before creating compiler
    std.debug.print("Creating test suite with allocator ptr: {}\n", .{@intFromPtr(allocator.ptr)});

    const test_alloc = allocator.alloc(u8, 1) catch |err| {
        std.debug.print("ERROR: Test suite allocator invalid: {}\n", .{err});
        return err;
    };
    allocator.free(test_alloc);

    const compiler_instance = PackagedCompiler.init(allocator);
    std.debug.print("Compiler instance created with allocator ptr: {}\n", .{@intFromPtr(compiler_instance.allocator.ptr)});

    // Pass the compiler instance, not the interface
    return SVTestSuite.init(allocator, compiler_instance);
}

// Comprehensive tests
test "sv-tests all available chapters" {
    const allocator = testing.allocator;

    var suite = try createTestSuite(allocator);
    defer suite.deinit();

    // Load all available tests
    try suite.loadAllAvailableTests();

    // Print statistics
    suite.printTestStatistics();

    // Run all tests
    try suite.runAllTests();
}

test "sv-tests lexical conventions (chapter 5)" {
    const allocator = testing.allocator;

    var suite = try createTestSuite(allocator);
    defer suite.deinit();

    try suite.loadTestsFromDirectory("sv-tests/tests/chapter-5");
    try suite.runAllTests();
}

test "sv-tests system tasks (chapter 20)" {
    const allocator = testing.allocator;

    var suite = try createTestSuite(allocator);
    defer suite.deinit();

    try suite.loadTestsFromDirectory("sv-tests/tests/chapter-20");
    try suite.runAllTests();
}

test "sv-tests data types (chapter 6)" {
    const allocator = testing.allocator;

    var suite = try createTestSuite(allocator);
    defer suite.deinit();

    try suite.loadTestsFromDirectory("sv-tests/tests/chapter-6");
    try suite.runAllTests();
}

test "sv-tests specific chapter" {
    const allocator = testing.allocator;

    var suite = try createTestSuite(allocator);
    defer suite.deinit();

    // Test specific chapter - change this to test different chapters
    try suite.runTestsByChapter("7");
}
