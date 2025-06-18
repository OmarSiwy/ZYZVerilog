# Objectives

Design a compiler/linter/cdc checker that can outperform the current ones on the market, and also implement **Incremental Compilation/Linting** to save time in development.

### Testing:

I recommend testing with the nix config for reproduciblity, but this project should work with Zig Version 0.14.1 without the nix config.

#### Without Nix:
Install Zig 0.14.1
```bash
git submodule update --init --recursive ./sv-tests
```

#### With Nix:
```bash
nix-shell # To install Zig 0.14.1
```

#### To Test:
```bash
zig build test # should pass
zig build test-sv # should pass
```
