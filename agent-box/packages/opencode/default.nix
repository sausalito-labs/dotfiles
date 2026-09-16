# OpenCode AI coding agent — prebuilt Linux x64 binary.
{ lib, stdenv, fetchurl }:

stdenv.mkDerivation rec {
  pname = "opencode";
  version = "1.18.31";

  src = fetchurl {
    url = "https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-linux-x64.tar.gz";
    hash = "sha256-6TEr517YA7dBX8Kuq9ofT+k4kSo5Zzdi3Aw4wOEeveQ=";
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
}