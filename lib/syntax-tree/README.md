Middle-End

## References:
https://github.com/rust-analyzer/rowan
https://github.com/salsa-rs/salsa
https://github.com/rust-lang/rust-analyzer/tree/master/crates/syntax
https://github.com/MikePopoloski/slang/blob/master/source/compilation

-> source/compilation/Compilation.cpp → Type mismatches, scope errors 
-> source/symbols/*.cpp → Declaration errors, binding failures

## Error Types:
Semantic Errors: Type mismatches, undeclared variables, scope errors, incompatible operands
Type Checking Errors: Invalid operands to binary expressions, assignment compatibility issues
Elaboration Errors: Module hierarchy resolution, parameter evaluation, interface connection errors
Name Resolution Errors: Multiple declarations in scope, accessing out-of-scope variables
Declaration Errors: Reserved identifier misuse, actual/formal parameter mismatch
