const std = @import("std");
const mem = std.mem;

/// Generic interface that any SystemVerilog compiler implementation must provide
pub const SVCompilerInterface = struct {
    const Self = @This();

    // Function pointer for compilation
    compileFn: *const fn (ptr: *anyopaque, allocator: mem.Allocator, source_code: []const u8) anyerror!CompileResult,

    // Function pointer for initialization (optional)
    initFn: ?*const fn (ptr: *anyopaque, allocator: mem.Allocator) anyerror!void = null,

    // Function pointer for cleanup (optional)
    deinitFn: ?*const fn (ptr: *anyopaque) void = null,

    // Function pointer for getting compiler info (optional)
    getInfoFn: ?*const fn (ptr: *anyopaque) CompilerInfo = null,

    // Pointer to the actual compiler implementation
    ptr: *anyopaque,

    /// Compile SystemVerilog source code
    pub fn compile(self: Self, allocator: mem.Allocator, source_code: []const u8) !CompileResult {
        return self.compileFn(self.ptr, allocator, source_code);
    }

    /// Initialize the compiler (if needed)
    pub fn init(self: Self, allocator: mem.Allocator) !void {
        if (self.initFn) |initFn| {
            return initFn(self.ptr, allocator);
        }
    }

    /// Clean up compiler resources (if needed)
    pub fn deinit(self: Self) void {
        if (self.deinitFn) |deinitFn| {
            deinitFn(self.ptr);
        }
    }

    /// Get compiler information
    pub fn getInfo(self: Self) CompilerInfo {
        if (self.getInfoFn) |getInfoFn| {
            return getInfoFn(self.ptr);
        }
        return CompilerInfo{};
    }
};

/// Result of a compilation operation
pub const CompileResult = struct {
    success: bool = true,
    ast: ?*anyopaque = null, // Opaque pointer to AST (compiler-specific)
    errors: []CompileError = &[_]CompileError{},
    warnings: []CompileWarning = &[_]CompileWarning{},
    metrics: CompileMetrics = .{},

    pub fn deinit(self: *CompileResult, allocator: mem.Allocator) void {
        for (self.errors) |err| {
            allocator.free(err.message);
        }
        if (self.errors.len > 0) {
            allocator.free(self.errors);
        }

        for (self.warnings) |warn| {
            allocator.free(warn.message);
        }
        if (self.warnings.len > 0) {
            allocator.free(self.warnings);
        }
    }
};

/// Compilation error information
pub const CompileError = struct {
    message: []const u8,
    line: u32 = 0,
    column: u32 = 0,
    file: ?[]const u8 = null,
    error_type: ErrorType = .syntax,

    pub const ErrorType = enum {
        lexical,
        syntax,
        semantic,
        type_check,
        elaboration,
        other,
    };
};

/// Compilation warning information
pub const CompileWarning = struct {
    message: []const u8,
    line: u32 = 0,
    column: u32 = 0,
    file: ?[]const u8 = null,
    warning_type: WarningType = .general,

    pub const WarningType = enum {
        unused,
        deprecated,
        performance,
        portability,
        general,
    };
};

/// Compilation performance metrics
pub const CompileMetrics = struct {
    compile_time_ns: u64 = 0,
    lexing_time_ns: u64 = 0,
    parsing_time_ns: u64 = 0,
    semantic_time_ns: u64 = 0,
    tokens_processed: u32 = 0,
    lines_processed: u32 = 0,
    ast_nodes_created: u32 = 0,
    memory_used_bytes: u64 = 0,
};

/// Information about the compiler implementation
pub const CompilerInfo = struct {
    name: []const u8 = "Unknown",
    version: []const u8 = "0.0.0",
    standard_support: []const StandardVersion = &[_]StandardVersion{},
    features: []const []const u8 = &[_][]const u8{},

    pub const StandardVersion = enum {
        ieee1364_1995,
        ieee1364_2001,
        ieee1364_2005,
        ieee1800_2005,
        ieee1800_2009,
        ieee1800_2012,
        ieee1800_2017,
        ieee1800_2023,
    };
};

/// Create a compiler interface adapter for any compiler type
pub fn createCompilerInterface(comptime CompilerType: type, compiler_instance: *CompilerType) SVCompilerInterface {
    const Impl = struct {
        fn compileFn(ptr: *anyopaque, allocator: mem.Allocator, source_code: []const u8) anyerror!CompileResult {
            const self: *CompilerType = @ptrCast(@alignCast(ptr));

            const start_time = std.time.nanoTimestamp();

            // Check if compiler has a compile method that returns CompileResult
            if (@hasDecl(CompilerType, "compileAdvanced")) {
                return self.compileAdvanced(allocator, source_code);
            }
            // Check if compiler has a simple compile method
            else if (@hasDecl(CompilerType, "compile")) {
                // Try calling with allocator first
                const result = if (@typeInfo(@TypeOf(self.compile)).Fn.params.len == 2)
                    self.compile(allocator, source_code)
                else
                    self.compile(source_code);

                const end_time = std.time.nanoTimestamp();
                const compile_time = end_time - start_time;

                // Handle void return (compilation succeeded)
                if (@TypeOf(result) == void or @TypeOf(result) == anyerror!void) {
                    result catch |err| {
                        return CompileResult{
                            .success = false,
                            .errors = &[_]CompileError{CompileError{
                                .message = try std.fmt.allocPrint(allocator, "Compilation failed: {}", .{err}),
                                .error_type = .syntax,
                            }},
                            .metrics = .{ .compile_time_ns = @intCast(compile_time) },
                        };
                    };

                    return CompileResult{
                        .success = true,
                        .metrics = .{
                            .compile_time_ns = @intCast(compile_time),
                            .lines_processed = @intCast(std.mem.count(u8, source_code, "\n") + 1),
                        },
                    };
                }

                // Handle other return types (assume success if no error)
                return CompileResult{
                    .success = true,
                    .ast = @ptrCast(&result),
                    .metrics = .{
                        .compile_time_ns = @intCast(compile_time),
                        .lines_processed = @intCast(std.mem.count(u8, source_code, "\n") + 1),
                    },
                };
            } else {
                return error.CompileMethodNotFound;
            }
        }

        fn initFn(ptr: *anyopaque, allocator: mem.Allocator) anyerror!void {
            _ = ptr;
            if (@hasDecl(CompilerType, "init")) {
                _ = CompilerType.init(allocator);
            }
        }

        fn deinitFn(ptr: *anyopaque) void {
            const self: *CompilerType = @ptrCast(@alignCast(ptr));
            if (@hasDecl(CompilerType, "deinit")) {
                self.deinit();
            }
        }

        fn getInfoFn(ptr: *anyopaque) CompilerInfo {
            const self: *CompilerType = @ptrCast(@alignCast(ptr));

            // Try to get info from compiler if it has getInfo method
            if (@hasDecl(CompilerType, "getInfo")) {
                return self.getInfo();
            }

            // Return default info
            return CompilerInfo{
                .name = @typeName(CompilerType),
                .version = "dev",
                .standard_support = &[_]CompilerInfo.StandardVersion{.ieee1800_2017},
            };
        }
    };

    return SVCompilerInterface{
        .compileFn = Impl.compileFn,
        .initFn = if (@hasDecl(CompilerType, "init")) Impl.initFn else null,
        .deinitFn = if (@hasDecl(CompilerType, "deinit")) Impl.deinitFn else null,
        .getInfoFn = Impl.getInfoFn,
        .ptr = compiler_instance,
    };
}

/// Benchmark a compiler implementation
pub const CompilerBenchmark = struct {
    allocator: mem.Allocator,
    interface: SVCompilerInterface,

    const Self = @This();

    pub fn init(allocator: mem.Allocator, interface: SVCompilerInterface) Self {
        return Self{
            .allocator = allocator,
            .interface = interface,
        };
    }

    pub fn benchmarkSingleFile(self: Self, source_code: []const u8, iterations: u32) !BenchmarkResult {
        var total_time: u64 = 0;
        var successful_runs: u32 = 0;
        var failed_runs: u32 = 0;

        for (0..iterations) |_| {
            const start = std.time.nanoTimestamp();
            const result = self.interface.compile(self.allocator, source_code) catch {
                failed_runs += 1;
                continue;
            };
            const end = std.time.nanoTimestamp();

            total_time += @intCast(end - start);
            successful_runs += 1;

            // Clean up result
            var mutable_result = result;
            mutable_result.deinit(self.allocator);
        }

        return BenchmarkResult{
            .total_iterations = iterations,
            .successful_runs = successful_runs,
            .failed_runs = failed_runs,
            .total_time_ns = total_time,
            .average_time_ns = if (successful_runs > 0) total_time / successful_runs else 0,
            .lines_of_code = @intCast(std.mem.count(u8, source_code, "\n") + 1),
        };
    }

    pub fn benchmarkMultipleFiles(self: Self, file_paths: []const []const u8) !BenchmarkResult {
        var total_time: u64 = 0;
        var successful_runs: u32 = 0;
        var failed_runs: u32 = 0;
        var total_lines: u32 = 0;

        for (file_paths) |file_path| {
            const source = std.fs.cwd().readFileAlloc(self.allocator, file_path, 10 * 1024 * 1024) catch {
                failed_runs += 1;
                continue;
            };
            defer self.allocator.free(source);

            const start = std.time.nanoTimestamp();
            const result = self.interface.compile(self.allocator, source) catch {
                failed_runs += 1;
                continue;
            };
            const end = std.time.nanoTimestamp();

            total_time += @intCast(end - start);
            successful_runs += 1;
            total_lines += @intCast(std.mem.count(u8, source, "\n") + 1);

            // Clean up result
            var mutable_result = result;
            mutable_result.deinit(self.allocator);
        }

        return BenchmarkResult{
            .total_iterations = @intCast(file_paths.len),
            .successful_runs = successful_runs,
            .failed_runs = failed_runs,
            .total_time_ns = total_time,
            .average_time_ns = if (successful_runs > 0) total_time / successful_runs else 0,
            .lines_of_code = total_lines,
        };
    }
};

pub const BenchmarkResult = struct {
    total_iterations: u32,
    successful_runs: u32,
    failed_runs: u32,
    total_time_ns: u64,
    average_time_ns: u64,
    lines_of_code: u32,

    pub fn printResults(self: BenchmarkResult) void {
        const total_time_ms = @as(f64, @floatFromInt(self.total_time_ns)) / 1_000_000.0;
        const average_time_ms = @as(f64, @floatFromInt(self.average_time_ns)) / 1_000_000.0;
        const lines_per_second = if (self.average_time_ns > 0)
            @as(f64, @floatFromInt(self.lines_of_code)) / (@as(f64, @floatFromInt(self.average_time_ns)) / 1_000_000_000.0)
        else
            0;

        std.debug.print("\n=== BENCHMARK RESULTS ===\n");
        std.debug.print("Total iterations: {}\n", .{self.total_iterations});
        std.debug.print("Successful runs: {}\n", .{self.successful_runs});
        std.debug.print("Failed runs: {}\n", .{self.failed_runs});
        std.debug.print("Success rate: {d:.1}%\n", .{@as(f64, @floatFromInt(self.successful_runs)) * 100.0 / @as(f64, @floatFromInt(self.total_iterations))});
        std.debug.print("Total time: {d:.2} ms\n", .{total_time_ms});
        std.debug.print("Average time per file: {d:.2} ms\n", .{average_time_ms});
        std.debug.print("Total lines processed: {}\n", .{self.lines_of_code});
        std.debug.print("Lines per second: {d:.0}\n", .{lines_per_second});
    }
};
