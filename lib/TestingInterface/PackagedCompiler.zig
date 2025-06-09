const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

// Import the shared interface
pub const SVInterface = @import("PackagedCompilerInterface.zig");
const CompileResult = SVInterface.CompileResult;
const CompileError = SVInterface.CompileError;
const CompileWarning = SVInterface.CompileWarning;
const CompileMetrics = SVInterface.CompileMetrics;
const CompilerInfo = SVInterface.CompilerInfo;

// Your parser's error types
pub const ParseError = error{
    SyntaxError,
    LexicalError,
    SemanticError,
    UnexpectedToken,
    UnexpectedEOF,
    InvalidIdentifier,
    InvalidNumber,
    InvalidString,
    UnsupportedFeature,
    OutOfMemory,
};

// Example AST node (you can define your own structure)
pub const ASTNode = union(enum) {
    module: Module,
    statement: Statement,
    expression: Expression,
    declaration: Declaration,

    pub const Module = struct {
        name: []const u8,
        ports: []Port,
        body: []Statement,
    };

    pub const Port = struct {
        name: []const u8,
        direction: enum { input, output, inout },
        data_type: []const u8,
    };

    pub const Statement = union(enum) {
        assignment: Assignment,
        always_block: AlwaysBlock,
        initial_block: InitialBlock,

        pub const Assignment = struct {
            target: []const u8,
            value: Expression,
        };

        pub const AlwaysBlock = struct {
            sensitivity_list: [][]const u8,
            body: []Statement,
        };

        pub const InitialBlock = struct {
            body: []Statement,
        };
    };

    pub const Expression = union(enum) {
        identifier: []const u8,
        number: Number,
        binary_op: BinaryOp,

        pub const Number = struct {
            value: i64,
            width: ?u32,
            base: enum { binary, octal, decimal, hex },
        };

        pub const BinaryOp = struct {
            left: *Expression,
            operator: []const u8,
            right: *Expression,
        };
    };

    pub const Declaration = union(enum) {
        variable: VariableDecl,
        parameter: ParameterDecl,

        pub const VariableDecl = struct {
            name: []const u8,
            data_type: []const u8,
            initial_value: ?Expression,
        };

        pub const ParameterDecl = struct {
            name: []const u8,
            value: Expression,
        };
    };
};

// Parse result containing the AST and any metadata
pub const ParseResult = struct {
    ast: ASTNode,
    warnings: [][]const u8,
    metadata: struct {
        module_count: u32,
        line_count: u32,
        has_synthesis_pragmas: bool,
    },

    pub fn deinit(self: *ParseResult, allocator: Allocator) void {
        // Free any allocated memory in the AST
        for (self.warnings) |warning| {
            allocator.free(warning);
        }
        allocator.free(self.warnings);
        // Add more cleanup as needed for your AST structure
    }
};

// Main SystemVerilog compiler struct
pub const YourSVParser = struct {
    allocator: Allocator,

    // Optional: Parser configuration
    options: ParseOptions = .{},

    // Optional: Internal state
    current_line: u32 = 1,
    current_column: u32 = 1,

    // Performance tracking
    last_compile_metrics: CompileMetrics = .{},

    const Self = @This();

    pub const ParseOptions = struct {
        strict_mode: bool = false,
        enable_extensions: bool = false,
        max_errors: u32 = 10,
        target_standard: enum { sv2005, sv2009, sv2012, sv2017, sv2023 } = .sv2017,
        enable_timing: bool = true,
        enable_warnings: bool = true,
    };

    // REQUIRED: Constructor
    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    // REQUIRED: Destructor
    pub fn deinit(self: *Self) void {
        // Clean up any internal state
        // Free any cached data, symbol tables, etc.
        _ = self;
    }

    // Simple compile method for backward compatibility
    pub fn compile(self: *Self, source_code: []const u8) !void {
        const result = try self.compileAdvanced(self.allocator, source_code);
        var mutable_result = result;
        defer mutable_result.deinit(self.allocator);

        if (!result.success) {
            return ParseError.SyntaxError;
        }
    }

    // Advanced compile method that returns detailed results
    pub fn compileAdvanced(self: *Self, allocator: Allocator, source_code: []const u8) !CompileResult {
        const start_time = std.time.nanoTimestamp();

        var errors = std.ArrayList(CompileError).init(allocator);
        defer errors.deinit();

        var warnings = std.ArrayList(CompileWarning).init(allocator);
        defer warnings.deinit();

        // Track performance metrics
        var metrics = CompileMetrics{
            .lines_processed = @intCast(std.mem.count(u8, source_code, "\n") + 1),
        };

        // 1. Lexical analysis
        const lexing_start = std.time.nanoTimestamp();
        const tokens = self.tokenize(source_code) catch |err| {
            try errors.append(CompileError{
                .message = try std.fmt.allocPrint(allocator, "Lexical analysis failed: {}", .{err}),
                .error_type = .lexical,
            });

            return CompileResult{
                .success = false,
                .ast = null,
                .errors = try errors.toOwnedSlice(),
                .warnings = try warnings.toOwnedSlice(),
                .metrics = metrics,
            };
        };
        defer allocator.free(tokens);

        const lexing_end = std.time.nanoTimestamp();
        metrics.lexing_time_ns = @intCast(lexing_end - lexing_start);
        metrics.tokens_processed = @intCast(tokens.len);

        // 2. Syntax analysis
        const parsing_start = std.time.nanoTimestamp();
        const ast = self.parseTokens(tokens) catch |err| {
            try errors.append(CompileError{
                .message = try std.fmt.allocPrint(allocator, "Syntax analysis failed: {}", .{err}),
                .error_type = .syntax,
            });

            return CompileResult{
                .success = false,
                .ast = null,
                .errors = try errors.toOwnedSlice(),
                .warnings = try warnings.toOwnedSlice(),
                .metrics = metrics,
            };
        };

        const parsing_end = std.time.nanoTimestamp();
        metrics.parsing_time_ns = @intCast(parsing_end - parsing_start);
        metrics.ast_nodes_created = self.countASTNodes(&ast);

        // 3. Semantic analysis
        const semantic_start = std.time.nanoTimestamp();
        self.validateSemantics(&ast) catch |err| {
            try errors.append(CompileError{
                .message = try std.fmt.allocPrint(allocator, "Semantic analysis failed: {}", .{err}),
                .error_type = .semantic,
            });

            return CompileResult{
                .success = false,
                .ast = null,
                .errors = try errors.toOwnedSlice(),
                .warnings = try warnings.toOwnedSlice(),
                .metrics = metrics,
            };
        };

        const semantic_end = std.time.nanoTimestamp();
        metrics.semantic_time_ns = @intCast(semantic_end - semantic_start);

        // Add some example warnings
        if (self.options.enable_warnings) {
            if (self.hasSynthesisPragmas(source_code)) {
                try warnings.append(CompileWarning{
                    .message = try allocator.dupe(u8, "Synthesis pragmas detected - may not be portable"),
                    .warning_type = .portability,
                });
            }

            if (std.mem.indexOf(u8, source_code, "always @(*)")) |_| {
                try warnings.append(CompileWarning{
                    .message = try allocator.dupe(u8, "Consider using always_comb for combinational logic"),
                    .warning_type = .performance,
                });
            }
        }

        const end_time = std.time.nanoTimestamp();
        metrics.compile_time_ns = @intCast(end_time - start_time);

        // Store metrics for later access
        self.last_compile_metrics = metrics;

        // Return result without allocating AST on heap - just store success
        return CompileResult{
            .success = true,
            .ast = null, // Don't allocate AST to avoid memory leaks
            .errors = try errors.toOwnedSlice(),
            .warnings = try warnings.toOwnedSlice(),
            .metrics = metrics,
        };
    }

    // Get compiler information
    pub fn getInfo(self: *Self) CompilerInfo {
        _ = self;
        return CompilerInfo{
            .name = "YourSVParser",
            .version = "1.0.0-dev",
            .standard_support = &[_]CompilerInfo.StandardVersion{
                .ieee1800_2017,
                .ieee1800_2012,
            },
            .features = &[_][]const u8{
                "lexical_analysis",
                "syntax_analysis",
                "semantic_analysis",
                "performance_metrics",
                "error_reporting",
            },
        };
    }

    // Configuration method
    pub fn setOptions(self: *Self, options: ParseOptions) void {
        self.options = options;
    }

    // Get detailed error information
    pub fn getLastMetrics(self: *Self) CompileMetrics {
        return self.last_compile_metrics;
    }

    // Create a compiler interface for this instance
    pub fn createInterface(self: *Self) SVInterface.SVCompilerInterface {
        return SVInterface.createCompilerInterface(YourSVParser, self);
    }

    // Internal methods (implement according to your parser design)
    fn tokenize(self: *Self, source: []const u8) ![]Token {
        // Debug: Check allocator validity
        if (@intFromPtr(self.allocator.ptr) == 0) {
            std.debug.print("ERROR: Allocator ptr is null!\n", .{});
            return ParseError.OutOfMemory;
        }

        // Debug: Test allocator with a small allocation
        const test_alloc = self.allocator.alloc(u8, 1) catch |err| {
            std.debug.print("ERROR: Allocator test failed: {}\n", .{err});
            return err;
        };
        self.allocator.free(test_alloc);

        std.debug.print("Tokenizing {} bytes with valid allocator\n", .{source.len});

        // Basic tokenizer implementation
        var tokens = std.ArrayList(Token).init(self.allocator);

        var i: usize = 0;
        var line: u32 = 1;
        var column: u32 = 1;

        while (i < source.len) {
            const c = source[i];

            switch (c) {
                ' ', '\t' => {
                    // Skip whitespace
                    i += 1;
                    column += 1;
                },
                '\n' => {
                    try tokens.append(Token{
                        .type = .newline,
                        .value = source[i .. i + 1],
                        .line = line,
                        .column = column,
                    });
                    i += 1;
                    line += 1;
                    column = 1;
                },
                ';' => {
                    try tokens.append(Token{
                        .type = .semicolon,
                        .value = source[i .. i + 1],
                        .line = line,
                        .column = column,
                    });
                    i += 1;
                    column += 1;
                },
                '(' => {
                    try tokens.append(Token{
                        .type = .lparen,
                        .value = source[i .. i + 1],
                        .line = line,
                        .column = column,
                    });
                    i += 1;
                    column += 1;
                },
                ')' => {
                    try tokens.append(Token{
                        .type = .rparen,
                        .value = source[i .. i + 1],
                        .line = line,
                        .column = column,
                    });
                    i += 1;
                    column += 1;
                },
                'a'...'z', 'A'...'Z', '_' => {
                    // Tokenize identifier or keyword
                    const start = i;
                    while (i < source.len and (std.ascii.isAlphanumeric(source[i]) or source[i] == '_')) {
                        i += 1;
                    }

                    const word = source[start..i];
                    const token_type = getKeywordType(word);

                    try tokens.append(Token{
                        .type = token_type,
                        .value = word,
                        .line = line,
                        .column = column,
                    });
                    column += @as(u32, @intCast(word.len));
                },
                '0'...'9' => {
                    // Tokenize number
                    const start = i;
                    while (i < source.len and (std.ascii.isDigit(source[i]) or source[i] == '_')) {
                        i += 1;
                    }

                    const number = source[start..i];
                    try tokens.append(Token{
                        .type = .number,
                        .value = number,
                        .line = line,
                        .column = column,
                    });
                    column += @as(u32, @intCast(number.len));
                },
                else => {
                    // Unknown character - create a generic token
                    try tokens.append(Token{
                        .type = .identifier,
                        .value = source[i .. i + 1],
                        .line = line,
                        .column = column,
                    });
                    i += 1;
                    column += 1;
                },
            }
        }

        try tokens.append(Token{
            .type = .eof,
            .value = "",
            .line = line,
            .column = column,
        });

        return tokens.toOwnedSlice();
    }

    fn parseTokens(self: *Self, tokens: []Token) !ASTNode {
        // Simple parser implementation
        _ = self;

        // Look for module declaration
        for (tokens, 0..) |token, i| {
            if (token.type == .module) {
                // Found module keyword, try to parse module name
                if (i + 1 < tokens.len and tokens[i + 1].type == .identifier) {
                    const module_name = tokens[i + 1].value;

                    return ASTNode{
                        .module = .{
                            .name = module_name,
                            .ports = &[_]ASTNode.Port{},
                            .body = &[_]ASTNode.Statement{},
                        },
                    };
                }
            }
        }

        // Default: return empty module
        return ASTNode{
            .module = .{
                .name = "unknown_module",
                .ports = &[_]ASTNode.Port{},
                .body = &[_]ASTNode.Statement{},
            },
        };
    }

    fn validateSemantics(self: *Self, ast: *const ASTNode) !void {
        // Basic semantic validation
        _ = self;

        switch (ast.*) {
            .module => |module| {
                if (module.name.len == 0) {
                    return ParseError.SemanticError;
                }
            },
            else => {},
        }
    }

    fn countASTNodes(self: *Self, ast: *const ASTNode) u32 {
        _ = self;
        switch (ast.*) {
            .module => |module| {
                return 1 + @as(u32, @intCast(module.ports.len)) + @as(u32, @intCast(module.body.len));
            },
            else => return 1,
        }
    }

    fn hasSynthesisPragmas(self: *Self, source: []const u8) bool {
        _ = self;
        return std.mem.indexOf(u8, source, "synthesis") != null or
            std.mem.indexOf(u8, source, "synopsys") != null;
    }

    fn getKeywordType(word: []const u8) Token.TokenType {
        if (std.mem.eql(u8, word, "module")) return .module;
        if (std.mem.eql(u8, word, "endmodule")) return .endmodule;
        if (std.mem.eql(u8, word, "input")) return .input;
        if (std.mem.eql(u8, word, "output")) return .output;
        if (std.mem.eql(u8, word, "inout")) return .inout;
        if (std.mem.eql(u8, word, "wire")) return .wire;
        if (std.mem.eql(u8, word, "reg")) return .reg;
        if (std.mem.eql(u8, word, "logic")) return .logic;
        if (std.mem.eql(u8, word, "always")) return .always;
        if (std.mem.eql(u8, word, "initial")) return .initial;
        if (std.mem.eql(u8, word, "assign")) return .assign;

        return .identifier;
    }
};

// Token definition for lexer
const Token = struct {
    type: TokenType,
    value: []const u8,
    line: u32,
    column: u32,

    const TokenType = enum {
        // Keywords
        module,
        endmodule,
        input,
        output,
        inout,
        wire,
        reg,
        logic,
        always,
        initial,
        assign,

        // Operators
        plus,
        minus,
        multiply,
        divide,
        assign_op,

        // Delimiters
        semicolon,
        comma,
        lparen,
        rparen,
        lbrace,
        rbrace,

        // Literals
        identifier,
        number,
        string,

        // Special
        eof,
        newline,
        comment,
    };
};
