{
  description = "Vendor-agnostic NixOS configuration for an agent box";

  inputs = {
    # Pin to the latest stable release for predictability.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs, ... }: {
    # Current machine: agent box VPS.
    # Add more hosts here as `hosts/<name>/configuration.nix` files.
    nixosConfigurations.agent-box = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hosts/agent-box/configuration.nix
      ];
    };
  };
}
