# Generic NixOS module for a headless gamedev box.
#
# This module is vendor-agnostic: it sets up the gamedev user, OpenCode, Godot,
# Tailscale, and the One Arcade demo server. It does NOT include any
# hardware-specific configuration, so a host file must import this module and
# provide a generated hardware-configuration.nix.

{ config, pkgs, lib, ... }:

let
  opencode = pkgs.stdenv.mkDerivation rec {
    pname = "opencode";
    version = "1.18.30";

    src = pkgs.fetchurl {
      url = "https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-linux-x64.tar.gz";
      hash = "sha256-VQByRoWBZUlv+FuhwrZI90IejiATv0GJpoDJ/45pnRc=";
    };

    dontBuild = true;
    sourceRoot = ".";

    installPhase = ''
      mkdir -p $out/bin
      install -m 755 opencode $out/bin/opencode
    '';

    meta = with lib; {
      description = "OpenCode AI coding agent";
      homepage = "https://opencode.ai";
      license = licenses.unfree;
      platforms = [ "x86_64-linux" ];
    };
  };

  # Official Godot 4.3 stable binary. Using the upstream release avoids waiting
  # for nixpkgs to bump versions.
  godot-4_3 = pkgs.stdenv.mkDerivation rec {
    pname = "godot";
    version = "4.3-stable";

    src = pkgs.fetchurl {
      url = "https://github.com/godotengine/godot/releases/download/${version}/Godot_v${version}_linux.x86_64.zip";
      hash = "sha256-feVkRLEwsQr4TRnH4M9jz56ZN+5LqUNkw7fdEUJTyiE=";
    };

    nativeBuildInputs = [ pkgs.unzip ];
    dontBuild = true;

    installPhase = ''
      mkdir -p $out/bin
      install -m 755 Godot_v${version}_linux.x86_64 $out/bin/godot
      ln -s $out/bin/godot $out/bin/godot4
    '';

    meta = with lib; {
      description = "Godot game engine";
      homepage = "https://godotengine.org";
      license = licenses.mit;
      platforms = [ "x86_64-linux" ];
    };
  };
in
{
  # ----------------------------------------------------------------------------
  # Defaults that can be overridden by the host config
  # ----------------------------------------------------------------------------
  networking.useDHCP = lib.mkDefault true;
  time.timeZone = lib.mkDefault "UTC";

  # ----------------------------------------------------------------------------
  # Users
  # ----------------------------------------------------------------------------
  users.users.gamedev = {
    isNormalUser = true;
    home = "/home/gamedev";
    description = "Game dev user";
    extraGroups = [ "wheel" "networkmanager" ];
    # The host configuration should override this with the actual SSH key.
    openssh.authorizedKeys.keys = lib.mkDefault [];
  };

  # Passwordless sudo for the gamedev user makes tmux/systemctl workflows less
  # annoying. Remove this if you prefer typing a password.
  security.sudo.wheelNeedsPassword = false;

  # ----------------------------------------------------------------------------
  # SSH
  # ----------------------------------------------------------------------------
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # ----------------------------------------------------------------------------
  # Tailscale private mesh
  # ----------------------------------------------------------------------------
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
  };

  # Everything except SSH is firewalled from the public internet. Tailscale
  # traffic comes in over its own interface and is trusted.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
    trustedInterfaces = [ "tailscale0" ];
  };

  # ----------------------------------------------------------------------------
  # System packages
  # ----------------------------------------------------------------------------
  environment.systemPackages = with pkgs; [
    git
    gh
    tmux
    curl
    wget
    unzip
    htop
    vim
    nano
    python3
    chromium
    chromedriver
    openssl
    godot-4_3
    opencode
  ];

  # Make Godot export templates discoverable at the path our build scripts expect.
  systemd.tmpfiles.rules = [
    "d /home/gamedev/.local/share/godot/export_templates 0755 gamedev gamedev -"
    "d /var/lib/opencode 0750 gamedev gamedev -"
    "d /home/gamedev/.config/opencode 0755 gamedev gamedev -"
    "d /home/gamedev/.local/share/opencode 0755 gamedev gamedev -"
  ];

  # ----------------------------------------------------------------------------
  # OpenCode web UI (tailnet-only)
  # ----------------------------------------------------------------------------
  systemd.services.opencode = {
    description = "OpenCode web interface";
    after = [ "network-online.target" "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "gamedev";
      Group = "gamedev";
      WorkingDirectory = "/home/gamedev";
      ExecStart = "${opencode}/bin/opencode web --port 4096 --hostname 0.0.0.0";
      Restart = "always";
      RestartSec = 5;
      EnvironmentFile = "/var/lib/opencode/opencode.env";
    };
  };

  # ----------------------------------------------------------------------------
  # One Arcade demo server (tailnet-only)
  # ----------------------------------------------------------------------------
  systemd.services.one-arcade-demo = {
    description = "One Arcade HTML5 demo server";
    after = [ "network-online.target" "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "gamedev";
      Group = "gamedev";
      WorkingDirectory = "/home/gamedev/one-arcade";
      ExecStart = "${pkgs.python3}/bin/python3 scripts/serve_demo.py --host 0.0.0.0 --port 8765 --directory build/html5 --https true";
      Restart = "always";
      RestartSec = 10;
    };
  };

  programs.tmux.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # This value determines the NixOS release with which your system is to be
  # compatible. Do not change it unless you know what you are doing.
  system.stateVersion = "24.11";
}
