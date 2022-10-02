{ 
  pkgs ? <nixpkgs>
}:

pkgs.stdenv.mkDerivation {
  name = "os-installer-snowflake-config";
  src = [ ./. ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/etc/os-installer
    cp config.yaml $out/etc/os-installer/
    cp -r scripts $out/etc/os-installer/
    cp -r icons $out/etc/os-installer/
    substituteInPlace $out/etc/os-installer/config.yaml \
      --replace /etc/os-installer $out/etc/os-installer
    runHook postInstall
  '';
}
