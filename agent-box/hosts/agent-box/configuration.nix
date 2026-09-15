# Machine-specific configuration for the agent box VPS.
#
# This file imports the generic agent module and only adds the pieces
# that depend on this particular machine: hardware config, hostname, disk
# layout, and the SSH key used for initial access.

{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/agent.nix
  ];

  nixpkgs.config.allowUnfree = true;

  boot.loader.grub = {
    enable = true;
    # The installer detects the boot disk from the running system and
    # patches this value before the first rebuild. Only change it manually
    # if the auto-detection fails.
    device = lib.mkDefault "/dev/sda";
    configurationLimit = 10;
  };

  networking.hostName = "agent-box";

  # Bootstrap: allow root SSH for first setup. After setup, change this to
  # "no" and run nixos-rebuild switch again.
  services.openssh.settings.PermitRootLogin = "yes";

  # Replace with your SSH public key before the first deploy if you want
  # key-based auth for the agent user.
  users.users.agent.openssh.authorizedKeys.keys = [
    # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... your@email"
  ];
}
