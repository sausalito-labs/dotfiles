{
  description = "Agent box: toolchain over plain Nix on Debian/Ubuntu (OpenCode installs via its official installer)";

  inputs = {
    # Pin to the latest stable release for predictability.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      packages = forAllSystems (system: rec {
        toolchain = (pkgsFor system).buildEnv {
          name = "agent-box-toolchain";
          paths = with pkgsFor system; [
            git
            gh
            tmux
            curl
            unzip
            htop
            python3
            openssl
          ];
        };
        default = toolchain;
      });

      devShells = forAllSystems (system: {
        default = (pkgsFor system).mkShell {
          packages = [ self.packages.${system}.toolchain ];
        };
      });
    };
}