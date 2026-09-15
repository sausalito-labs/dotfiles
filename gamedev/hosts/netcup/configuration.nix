# Machine-specific configuration for the netcup VPS.
#
# This file imports the generic gamedev-box module and only adds the pieces
# that depend on this particular machine: hardware config, hostname, disk
# layout, and the SSH key used for initial access.

{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/gamedev-box.nix
  ];

  boot.loader.grub = {
    enable = true;
    # Netcup VPSes usually expose the disk as /dev/sda. Verify with `lsblk`
    # before running nixos-install and adjust if needed.
    device = lib.mkDefault "/dev/sda";
    configurationLimit = 10;
  };

  networking.hostName = "netcup-gamedev";

  # Replace with your SSH public key before the first deploy.
  users.users.gamedev.openssh.authorizedKeys.keys = [
    # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... your@email"
  ];
}
