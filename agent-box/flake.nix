{
  description = "Agent box: OpenCode + toolchain over plain Nix on Debian/Ubuntu";

  inputs = {
    # Pin to the latest stable release for predictability.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system} = rec {
        opencode = pkgs.callPackage ./packages/opencode/default.nix { };
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
        default = opencode;
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [ self.packages.${system}.opencode ];
      };
    };
}