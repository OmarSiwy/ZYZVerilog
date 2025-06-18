{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    # Build essentials (GCC, linker, Ninja, etc.)
    rustup
    gcc
    binutils
    cmake
    python313Packages.ninja

    # Development tools
    cargo-edit
    cargo-expand

    # System dependencies
    pkg-config
    openssl
  ];

  # Environment variables for optimal compilation
  RUST_BACKTRACE = "1";
  RUSTFLAGS = "-C target-cpu=native -Z share-generics=y -Z threads=8";
  CARGO_INCREMENTAL = "1";

  # Nightly features
  RUSTC_BOOTSTRAP = "1";

  shellHook = ''
    echo "Rust development environment loaded!"

    # Install/set nightly if not already done
    rustup toolchain install nightly
    rustup default nightly
    rustup component add rust-src rust-analyzer clippy rustfmt

    echo "Nightly Rust with incremental compilation optimizations"
    rustc --version
    cargo --version
    gcc --version
  '';
}
