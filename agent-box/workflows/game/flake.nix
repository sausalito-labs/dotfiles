{
  description = "Game development workflow";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      devShells = forAllSystems (system:
        let pkgs = pkgsFor system; in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              godot_4
              godot_4-export-templates
              python3
              unzip
              curl
            ];

            # Godot looks for export templates in
            # ~/.local/share/godot/export_templates/<version>/. The store path
            # from godot_4-export-templates is that exact directory, so symlink
            # it into place instead of hand-downloading/renaming a 1GB tpz.
            shellHook = ''
              templates_root="$HOME/.local/share/godot/export_templates"
              version="$(cat ${pkgs.godot_4-export-templates}/version.txt)"
              target="$templates_root/$version"
              mkdir -p "$templates_root"
              if [[ "$(readlink "$target" 2>/dev/null)" != "${pkgs.godot_4-export-templates}" ]]; then
                ln -sfn "${pkgs.godot_4-export-templates}" "$target"
                echo "Linked Godot export templates -> $target"
              fi
            '';
          };
        });
    };
}