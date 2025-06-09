const std = @import("std");

// CLI Result Types
const CLIResult = enum {
    success,
    help_requested,
    invalid_arguments,
    missing_required_args,
    file_not_found,
    compilation_error,
};

const Config = struct {
    debug: bool = false,
    verbose: bool = false,
    recursive: bool = false,
    output_lint_format: bool = false,
    directories: std.ArrayList([]const u8),
    files: std.ArrayList([]const u8),

    fn init(allocator: std.mem.Allocator) Config {
        return .{
            .directories = std.ArrayList([]const u8).init(allocator),
            .files = std.ArrayList([]const u8).init(allocator),
        };
    }

    fn deinit(self: *Config) void {
        self.directories.deinit();
        self.files.deinit();
    }

    fn isValid(self: *const Config) bool {
        // Must have either files or directories
        if (self.files.items.len == 0 and self.directories.items.len == 0) {
            return false;
        }

        // If recursive is set, must have directories
        if (self.recursive and self.directories.items.len == 0) {
            return false;
        }

        return true;
    }
};

// CLI Module
const CLI = struct {
    fn printHelp() void {
        std.debug.print(
            \\Usage: mycompiler [OPTIONS]
            \\
            \\Options:
            \\  -d, --debug                    Enable debug mode
            \\  -v, --verbose                  Enable verbose output
            \\  -r, --recursively              Search directories recursively (requires --directory)
            \\  --directory <dir1> <dir2>...   Specify directories to process
            \\  --files <file1> <file2>...     Specify files to process (.v or .sv)
            \\  --output-in-lint-format        Output in linter format
            \\  -h, --help                     Show this help message
            \\
            \\Examples:
            \\  mycompiler --files main.v utils.sv
            \\  mycompiler --directory src --recursively
            \\  mycompiler -d -v --files test.v --output-in-lint-format
            \\
        );
    }

    fn parseArgs(allocator: std.mem.Allocator, config: *Config) !CLIResult {
        var args = try std.process.argsWithAllocator(allocator);
        defer args.deinit();
        _ = args.skip(); // skip program name

        var expect_directories = false;
        var expect_files = false;

        while (args.next()) |arg| {
            // Handle expected values for multi-value options
            if (expect_directories) {
                if (std.mem.startsWith(u8, arg, "-")) {
                    expect_directories = false;
                    // Fall through to handle this as a new flag
                } else {
                    try config.directories.append(arg);
                    continue;
                }
            }

            if (expect_files) {
                if (std.mem.startsWith(u8, arg, "-")) {
                    expect_files = false;
                    // Fall through to handle this as a new flag
                } else {
                    // Validate file extension
                    if (std.mem.endsWith(u8, arg, ".v") or std.mem.endsWith(u8, arg, ".sv")) {
                        try config.files.append(arg);
                        continue;
                    } else {
                        std.debug.print("Error: File '{s}' must have .v or .sv extension\n", .{arg});
                        return CLIResult.invalid_arguments;
                    }
                }
            }

            // Handle flags
            if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                CLI.printHelp();
                return CLIResult.help_requested;
            } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--debug")) {
                config.debug = true;
            } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
                config.verbose = true;
            } else if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--recursively")) {
                config.recursive = true;
            } else if (std.mem.eql(u8, arg, "--output-in-lint-format")) {
                config.output_lint_format = true;
            } else if (std.mem.eql(u8, arg, "--directory")) {
                expect_directories = true;
            } else if (std.mem.eql(u8, arg, "--files")) {
                expect_files = true;
            } else {
                std.debug.print("Error: Unknown argument '{s}'\n", .{arg});
                std.debug.print("Use -h or --help for usage information\n", .{});
                return CLIResult.invalid_arguments;
            }
        }

        return CLIResult.success;
    }

    fn validateConfig(config: *const Config) CLIResult {
        if (!config.isValid()) {
            if (config.recursive and config.directories.items.len == 0) {
                std.debug.print("Error: --recursively requires --directory to be specified\n", .{});
            } else {
                std.debug.print("Error: Must specify either --files or --directory\n", .{});
            }
            return CLIResult.missing_required_args;
        }

        // Check if files exist
        for (config.files.items) |file| {
            const file_exists = std.fs.cwd().access(file, .{}) catch false;
            if (!file_exists) {
                std.debug.print("Error: File '{s}' not found\n", .{file});
                return CLIResult.file_not_found;
            }
        }

        // Check if directories exist
        for (config.directories.items) |dir| {
            std.fs.cwd().access(dir, .{}) catch {
                std.debug.print("Error: Directory '{s}' not found\n", .{dir});
                return CLIResult.file_not_found;
            };
        }

        return CLIResult.success;
    }

    fn setup(allocator: std.mem.Allocator, config: *Config) !CLIResult {
        const parse_result = try CLI.parseArgs(allocator, config);
        if (parse_result != .success) return parse_result;

        return CLI.validateConfig(config);
    }
};

// Compiler Module
const Compiler = struct {
    fn printConfig(config: *const Config) void {
        std.debug.print("Configuration:\n", .{});
        std.debug.print("  Debug: {}\n", .{config.debug});
        std.debug.print("  Verbose: {}\n", .{config.verbose});
        std.debug.print("  Recursive: {}\n", .{config.recursive});
        std.debug.print("  Lint Format: {}\n", .{config.output_lint_format});

        if (config.directories.items.len > 0) {
            std.debug.print("  Directories:\n", .{});
            for (config.directories.items) |dir| {
                std.debug.print("    - {s}\n", .{dir});
            }
        }

        if (config.files.items.len > 0) {
            std.debug.print("  Files:\n", .{});
            for (config.files.items) |file| {
                std.debug.print("    - {s}\n", .{file});
            }
        }
    }

    fn processFiles(config: *const Config) CLIResult {
        for (config.files.items) |file| {
            if (config.debug) {
                std.debug.print("Processing file: {s}\n", .{file});
            }
            // TODO: Add your file processing logic here
            // If compilation fails, return CLIResult.compilation_error;
        }
        return CLIResult.success;
    }

    fn processDirectories(config: *const Config) CLIResult {
        for (config.directories.items) |dir| {
            if (config.debug) {
                std.debug.print("Processing directory: {s} (recursive: {})\n", .{ dir, config.recursive });
            }
            // TODO: Add your directory processing logic here
            // If compilation fails, return CLIResult.compilation_error;
        }
        return CLIResult.success;
    }

    fn outputResults(config: *const Config) void {
        if (config.output_lint_format) {
            std.debug.print("// Lint format output:\n", .{});
            std.debug.print("// line number | Error Type | Error Description | Hint To Fix\n", .{});
            // TODO: Output actual lint results
        } else {
            std.debug.print("Compilation completed successfully.\n", .{});
        }
    }

    fn run(config: *const Config) CLIResult {
        if (config.verbose) {
            Compiler.printConfig(config);
        }

        std.debug.print("Starting compilation...\n", .{});

        // Process files
        const file_result = Compiler.processFiles(config);
        if (file_result != .success) return file_result;

        // Process directories
        const dir_result = Compiler.processDirectories(config);
        if (dir_result != .success) return dir_result;

        // Output results
        Compiler.outputResults(config);

        return CLIResult.success;
    }
};

// Main Application Controller
const App = struct {
    fn run(allocator: std.mem.Allocator) !CLIResult {
        var config = Config.init(allocator);
        defer config.deinit();

        const cli_result = try CLI.setup(allocator, &config);

        switch (cli_result) {
            .success => return Compiler.run(&config),
            .help_requested => return CLIResult.success,
            else => return cli_result,
        }
    }
};

// Compiler Flow - Single function call
pub fn CompilerFlow() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const result = try App.run(allocator);

    switch (result) {
        .success, .help_requested => {},
        else => std.process.exit(1),
    }
}
