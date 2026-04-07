{
  description = "Lisette - a little language inspired by Rust that compiles to Go";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, rust-overlay }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ (import rust-overlay) ];
          };
          rustToolchain = (pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml).override {
            extensions = [ "llvm-tools-preview" ];
          };
        in
        {
          default = pkgs.mkShell {
            buildInputs = [
              # Rust
              rustToolchain
              pkgs.cargo-deny
              pkgs.cargo-insta
              pkgs.cargo-llvm-cov
              pkgs.cargo-shear
              pkgs.cargo-watch

              # Go
              pkgs.go
              pkgs.golangci-lint

              # Tools
              pkgs.just
              pkgs.lefthook
            ];
          };
        }
      );
    };
}
