{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils
  }:
  # Nix supports many different os/arch combinations, but in practice we mostly care about support x86_64 and arm for linux and darwin (macOS)
  # The list maintained by as "defaultSystems" is exactly this, i.e. ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"]
  flake-utils.lib.eachDefaultSystem (
    system: let
      pkgs = import nixpkgs{inherit system;};
    in rec {
      devShells.default = pkgs.mkShell {
          packages = [
            pkgs.vendir
            pkgs.go-jsonnet
            pkgs.kubernetes-helm
            pkgs.kustomize
          ];
      };
      defaultPackage = devShells.default; # Allow nix build to also pick up the shell by default
    }
  );
}
