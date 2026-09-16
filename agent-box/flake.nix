{
  description = "Agent box: toolchain over plain Nix on Debian/Ubuntu (OpenCode installs via its official installer)";

  inputs = {
    # Pin to the latest stable release for predictability.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      packages.${system} = rec {
        toolchain = pkgs.buildEnv {
          name = "agent-box-toolchain";
          paths = with pkgs; [
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
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [ self.packages.${system}.toolchain ];
      };
    };
}
