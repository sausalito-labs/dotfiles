{
  description = "Vendor-agnostic NixOS configuration for a headless gamedev box";

  inputs = {
    # Pin to the latest stable release for predictability.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
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
