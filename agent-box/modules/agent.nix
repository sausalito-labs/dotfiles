# Generic NixOS module for an agent box.
#
# This module is vendor-agnostic: it sets up the agent user, OpenCode,
# Tailscale, and SSH. It does NOT include any hardware-specific configuration,
# so a host file must import this module and provide a generated
# hardware-configuration.nix.

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
  users.users.agent = {
    isNormalUser = true;
    home = "/home/agent";
    description = "Agent user";
    extraGroups = [ "wheel" "networkmanager" ];
    # The host configuration should override this with the actual SSH key.
    openssh.authorizedKeys.keys = lib.mkDefault [];
  };

  # Passwordless sudo for the agent user makes tmux/systemctl workflows less
  # annoying. Remove this if you prefer typing a password.
  security.sudo.wheelNeedsPassword = false;

  # ----------------------------------------------------------------------------
  # SSH
  # ----------------------------------------------------------------------------
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = lib.mkDefault "no";
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
    python3
    openssl
    opencode
  ];

  # Make Godot export templates and OpenCode state directories discoverable.
  # Agent environments live under /etc/nixos/dotfiles/agent-box/agent/envs and are
  # symlinked into /home/agent/envs for convenience.
  systemd.tmpfiles.rules = [
    "d /home/agent/.local/share/godot/export_templates 0755 agent agent -"
    "d /var/lib/opencode 0750 agent agent -"
    "d /home/agent/.config/opencode 0755 agent agent -"
    "d /home/agent/.local/share/opencode 0755 agent agent -"
    "d /etc/nixos/dotfiles/agent-box/agent/envs 0755 agent agent -"
    "L+ /home/agent/envs - - - - /etc/nixos/dotfiles/agent-box/agent/envs"
  ];

  # ----------------------------------------------------------------------------
  # OpenCode web UI (tailnet-only)
  # ----------------------------------------------------------------------------
  systemd.services.opencode = {
    description = "OpenCode web interface";
    after = [ "network-online.target" "tailscaled.service" ];
    wants = [ "network-online.target" "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "agent";
      Group = "agent";
      WorkingDirectory = "/home/agent";
      ExecStart = "${opencode}/bin/opencode web --port 4096 --hostname 0.0.0.0";
      Restart = "always";
      RestartSec = 5;
      EnvironmentFile = "/var/lib/opencode/opencode.env";
    };
  };

  programs.tmux.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # This value determines the NixOS release with which your system is to be
  # compatible. Do not change it unless you know what you are doing.
  system.stateVersion = "24.11";
}
