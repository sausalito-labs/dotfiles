{
  description = "Vendor-agnostic NixOS configuration for a headless gamedev box";

  inputs = {
    # Pin to unstable for the freshest Godot/Chromium packages.
    # Change to github:NixOS/nixpkgs/nixos-24.11 if you prefer a stable release.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }: {
    # Current machine: netcup VPS.
    # Add more hosts here as `hosts/<name>/configuration.nix` files.
    nixosConfigurations.netcup = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hosts/netcup/configuration.nix
      ];
    };
  };
}
