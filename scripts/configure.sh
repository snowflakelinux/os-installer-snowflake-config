#! /bin/sh
set -e
# The script gets called with the environment variables from the install script
# (see install.sh) and these additional variables:
# OSI_USER_NAME          : User's name. Not ASCII-fied
# OSI_USER_AUTOLOGIN     : Whether to autologin the user
# OSI_USER_PASSWORD      : User's password. Can be empty if autologin is set.
# OSI_FORMATS            : Locale of formats to be used
# OSI_TIMEZONE           : Timezone to be used
# OSI_ADDITIONAL_SOFTWARE: Space-separated list of additional packages to install

# sanity check that all variables were set
if [ -z ${OSI_LOCALE+x} ] || \
   [ -z ${OSI_DEVICE_PATH+x} ] || \
   [ -z ${OSI_DEVICE_IS_PARTITION+x} ] || \
   [ -z ${OSI_DEVICE_EFI_PARTITION+x} ] || \
   [ -z ${OSI_USE_ENCRYPTION+x} ] || \
   [ -z ${OSI_ENCRYPTION_PIN+x} ] || \
   [ -z ${OSI_USER_NAME+x} ] || \
   [ -z ${OSI_USER_AUTOLOGIN+x} ] || \
   [ -z ${OSI_USER_PASSWORD+x} ] || \
   [ -z ${OSI_FORMATS+x} ] || \
   [ -z ${OSI_TIMEZONE+x} ] || \
   [ -z ${OSI_ADDITIONAL_SOFTWARE+x} ]
then
    echo "Installer script called without all environment variables set!"
    exit 1
fi

# Check if /tmp/os-installer exists
if [ ! -d /tmp/os-installer ]
then
    echo "Installer script called without /tmp/os-installer existing!"
    exit 1
fi

echo 'Configuration started.'
echo ''
echo 'Variables set to:'
echo 'OSI_LOCALE               ' $OSI_LOCALE
echo 'OSI_DEVICE_PATH          ' $OSI_DEVICE_PATH
echo 'OSI_DEVICE_IS_PARTITION  ' $OSI_DEVICE_IS_PARTITION
echo 'OSI_DEVICE_EFI_PARTITION ' $OSI_DEVICE_EFI_PARTITION
echo 'OSI_USE_ENCRYPTION       ' $OSI_USE_ENCRYPTION
echo 'OSI_ENCRYPTION_PIN       ' $OSI_ENCRYPTION_PIN
echo 'OSI_USER_NAME            ' $OSI_USER_NAME
echo 'OSI_USER_AUTOLOGIN       ' $OSI_USER_AUTOLOGIN
# echo 'OSI_USER_PASSWORD        ' $OSI_USER_PASSWORD
echo 'OSI_FORMATS              ' $OSI_FORMATS
echo 'OSI_TIMEZONE             ' $OSI_TIMEZONE
echo 'OSI_ADDITIONAL_SOFTWARE  ' $OSI_ADDITIONAL_SOFTWARE
echo ''

NIXOSVER=$(nixos-version | head -c 5)
USERNAME=\"$(echo $OSI_USER_NAME | iconv -f utf-8 -t ascii//translit | sed 's/[[:space:]]//g' | tr '[:upper:]' '[:lower:]')\"
KEYBOARD_LAYOUT=$(gsettings get org.gnome.desktop.input-sources sources | grep -o "'[^']*')" | sed "s/'//" | sed "s/')//" | head -n 1 | cut -f1 -d"+")
KEYBOARD_VARIANT=$(gsettings get org.gnome.desktop.input-sources sources | grep -o "'[^']*')" | sed "s/'//" | sed "s/')//" | head -n 1 | grep -Po '\+.*' | cut -c2-)

if [[ $OSI_DEVICE_IS_PARTITION == 1 ]]
then
  DISK=$(lsblk $OSI_DEVICE_PATH -npdbro pkname)
else
  DISK=$OSI_DEVICE_PATH
fi

if [[ $OSI_ADDITIONAL_SOFTWARE == *"prime"* ]]
then
  awk_program='function generate_string (str) {
      str = substr(str, 6) # Trim leading 0000:
      str = gensub(/\./, ":", "g", str) # Replace . with :
      str = gensub(/(0+)([0-9])/, "\\2", "g", str) # Remove leading 0
      split(str, strArr, ":") # Transform each part into decimal
      out = ""
      for (i in strArr) {
       out = out":"strtonum("0x"strArr[i])
      }
      return substr(out, 2)
  }
  /(VGA|3D|Display).*AMD.*/ { print "AMD", $1, generate_string($1) }
  /(VGA|3D|Display).*NVIDIA.*/ { print "NVIDIA", $1, generate_string($1) }
  /(VGA|3D|Display).*Intel.*/ { print "INTEL", $1, generate_string($1) }
  '

  PCIOUT=$(awk "$awk_program" <(lspci -D))
  INTELPCI=$(echo "$PCIOUT" | grep INTEL | awk '{ print $3 }')
  INTELPCIORIG=$(echo "$PCIOUT" | grep INTEL | awk '{ print $2 }')
  AMDPCI=$(echo "$PCIOUT" | grep AMD | awk '{ print $3 }')
  AMDPCIORIG=$(echo "$PCIOUT" | grep AMD | awk '{ print $2 }')
  NVIDIAPCI=$(echo "$PCIOUT" | grep NVIDIA | awk '{ print $3 }')
  NVIDIAPCIORIG=$(echo "$PCIOUT" | grep NVIDIA | awk '{ print $2 }')

  if [[ ! -z "$NVIDIAPCI" ]]
  then
    echo 'NVIDIA PCI ID: ' $NVIDIAPCIORIG ' -> ' $NVIDIAPCI
    if [[ ! -z "$INTELPCI" ]]
    then
      echo 'INTEL PCI ID: ' $INTELPCIORIG ' -> ' $INTELPCI
      INTELPRIME=1
    elif [[ ! -z "$AMDPCI" ]]
    then
      echo 'AMD PCI ID: ' $AMDGPUORIG ' -> ' $AMDPCI
      AMDPRIME=1
    fi
  fi
elif [[ $OSI_ADDITIONAL_SOFTWARE == *"nvidia"* ]]
then
  NVIDIA=1
fi

FLAKETXT="{
  inputs = {
    nixpkgs.url = \"github:NixOS/nixpkgs/nixos-unstable\";
    snowflake.url = \"github:snowflakelinux/snowflake-modules\";
    nix-data.url = \"github:snowflakelinux/nix-data\";
    nix-software-center.url = \"github:vlinkz/nix-software-center\";
    nixos-conf-editor.url = \"github:vlinkz/nixos-conf-editor\";
    snow.url = \"github:snowflakelinux/snow\";
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      system = \"x86_64-linux\";
    in
    {
      nixosConfigurations.snowflakeos = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./configuration.nix
          ./snowflake.nix
          inputs.snowflake.nixosModules.snowflake
          inputs.nix-data.nixosModules.\${system}.nix-data
        ];
        specialArgs = { inherit inputs; inherit system; };
    };
  };
}
"

SNOWFLAKETXT="{ config, pkgs, inputs, system, ... }:

{
  environment.systemPackages = [
    inputs.nix-software-center.packages.\${system}.nix-software-center
    inputs.nixos-conf-editor.packages.\${system}.nixos-conf-editor
    inputs.snow.packages.\${system}.snow
    pkgs.git # For rebuiling with github flakes
  ];
  programs.nix-data = {
    systemconfig = \"/etc/nixos/configuration.nix\";
    flake = \"/etc/nixos/flake.nix\";
    flakearg = \"snowflakeos\";
  };
  snowflakeos.gnome.enable = true;
  snowflakeos.osInfo.enable = true;
}
"

CFGHEAD="# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:
"

CFGNVIDIAOFFLOAD="let
  nvidia-offload = pkgs.writeShellScriptBin \"nvidia-offload\" ''
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __VK_LAYER_NV_optimus=NVIDIA_only
    exec -a \"\$0\" \"\$@\"
  '';
in
"

CFGIMPORTS="{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

"
CFGBOOTEFI="  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = \"/boot/efi\";

"

CFGBOOTBIOS="  # Bootloader.
  boot.loader.grub.enable = true;
  boot.loader.grub.device = \"$DISK\";
  boot.loader.grub.useOSProber = true;

"

CFGBOOTCRYPT="  # Setup keyfile
  boot.initrd.secrets = {
    \"/crypto_keyfile.bin\" = null;
  };

"

CFGBOOTGRUBCRYPT="  # Enable grub cryptodisk
  boot.loader.grub.enableCryptodisk=true;

"

CFGSWAPCRYPT="  # Enable swap on luks
  boot.initrd.luks.devices.\"@@swapdev@@\".device = \"/dev/disk/by-uuid/@@swapuuid@@\";
  boot.initrd.luks.devices.\"@@swapdev@@\".keyFile = \"/crypto_keyfile.bin\";

"

CFGKERNEL="  # Use the latest kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;
  
"

CFGNVIDIA="  # Use NVIDIA Proprietary drivers
  services.xserver.videoDrivers = [ \"nvidia\" ];
  hardware.opengl.extraPackages = with pkgs; [
    vaapiVdpau
  ];

"

CFGINTELPRIME="  # Use NVIDIA Prime with NVIDIA Proprietary drivers
  hardware.nvidia.modesetting.enable = true;
  hardware.nvidia.powerManagement.enable = true;
  hardware.nvidia.prime = {
    sync.enable = true;
    intelBusId = \"PCI:$INTELPCI\";
    nvidiaBusId = \"PCI:$NVIDIAPCI\";
  };
  services.xserver.videoDrivers = [ \"nvidia\" ];
  hardware.opengl.extraPackages = with pkgs; [
    vaapiVdpau
  ];

"

CFGAMDPRIME="  # Use NVIDIA Prime with NVIDIA Proprietary drivers
  hardware.nvidia.modesetting.enable = true;
  hardware.nvidia.powerManagement.enable = true;
  hardware.nvidia.prime = {
    sync.enable = true;
    amdgpuBusId = \"PCI:$AMDPCI\";
    nvidiaBusId = \"PCI:$NVIDIAPCI\";
  };
  services.xserver.videoDrivers = [ \"nvidia\" ];
  hardware.opengl.extraPackages = with pkgs; [
    vaapiVdpau
  ];

"

CFGNETWORK="  # Define your hostname.
  networking.hostName = \"snowflakeos\";

  # Enable networking
  networking.networkmanager.enable = true;

"

CFGTIME="  # Set your time zone.
  time.timeZone = \"$OSI_TIMEZONE\";

"

CFGLOCALE="  # Select internationalisation properties.
  i18n.defaultLocale = \"$OSI_LOCALE\";

"

CFGLOCALEEXTRAS="  i18n.extraLocaleSettings = {
    LC_ADDRESS = \"$OSI_FORMATS\";
    LC_IDENTIFICATION = \"$OSI_FORMATS\";
    LC_MEASUREMENT = \"$OSI_FORMATS\";
    LC_MONETARY = \"$OSI_FORMATS\";
    LC_NAME = \"$OSI_FORMATS\";
    LC_NUMERIC = \"$OSI_FORMATS\";
    LC_PAPER = \"$OSI_FORMATS\";
    LC_TELEPHONE = \"$OSI_FORMATS\";
    LC_TIME = \"$OSI_FORMATS\";
  };

"

CFGKEYMAP="  # Configure keymap in X11
  services.xserver = {
    layout = \"$KEYBOARD_LAYOUT\";
    xkbVariant = \"$KEYBOARD_VARIANT\";
  };
  console.useXkbConfig = true;

"

CFGGNOME="  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

"

CFGMISC="  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

"

CFGUSERS="  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.$USERNAME = {
    isNormalUser = true;
    description = \"$OSI_USER_NAME\";
    extraGroups = [ \"wheel\" \"networkmanager\" \"dialout\" ];
  };

"

CFGAUTOLOGIN="  # Enable automatic login for the user.
  services.xserver.displayManager.autoLogin.enable = true;
  services.xserver.displayManager.autoLogin.user = $USERNAME;

"

CFGAUTOLOGINGDM="  # Workaround for GNOME autologin: https://github.com/NixOS/nixpkgs/issues/103746#issuecomment-945091229
  systemd.services.\"getty@tty1\".enable = false;
  systemd.services.\"autovt@tty1\".enable = false;

"

CFGUNFREE="  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  environment.sessionVariables.NIXPKGS_ALLOW_UNFREE = \"1\";

"

CFGPKGS="  # List packages installed in system profile.
  environment.systemPackages = with pkgs; [
    firefox
  ];

"

CFGPKGSPRIME="  # List packages installed in system profile.
  environment.systemPackages = with pkgs; [
    nvidia-offload
    firefox
  ];

"

CFGTAIL="  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = \"$NIXOSVER\"; # Did you read the comment?

}
"

# Create flake.nix
pkexec sh -c 'echo -n "$0" > /tmp/os-installer/etc/nixos/flake.nix' "$FLAKETXT"

# Create snowflake.nix
pkexec sh -c 'echo -n "$0" > /tmp/os-installer/etc/nixos/snowflake.nix' "$SNOWFLAKETXT"

# Create configuration.nix
pkexec sh -c 'echo -n "$0" > /tmp/os-installer/etc/nixos/configuration.nix' "$CFGHEAD"
if [[ $INTELPRIME == 1 || $AMDPRIME == 1 ]]
then
  pkexec sh -c 'echo -n "$0" >> /tmp/os-installer/etc/nixos/configuration.nix' "$CFGNVIDIAOFFLOAD"
fi
pkexec sh -c 'echo -n "$0" >> /tmp/os-installer/etc/nixos/configuration.nix' "$CFGIMPORTS"
if [[ -d /sys/firmware/efi/efivars ]]
then
    pkexec sh -c 'echo -n "$0" >> /tmp/os-installer/etc/nixos/configuration.nix' "$CFGBOOTEFI"
else
    pkexec sh -c 'echo -n "$0" >> /tmp/os-installer/etc/nixos/configuration.nix' "$CFGBOOTBIOS"
fi
pkexec sh -c 'echo -n "$0" >> /tmp/os-installer/etc/nixos/configuration.nix' "$CFGKERNEL"
if [[ $INTELPRIME == 1 ]]
then
  pkexec sh -c 'echo -n "$0" >> /tmp/os-installer/etc/nixos/configuration.nix' "$CFGINTELPRIME"
elif [[ $AMDPRIME == 1 ]]
then
  pkexec sh -c 'echo -n "$0" >> /tmp/os-installer/etc/nixos/configuration.nix' "$CFGAMDPRIME"
elif [[ $NVIDIA == 1 ]]
then
  pkexec sh -c 'echo -n "$0" >> /tmp/os-installer/etc/nixos/configuration.nix' "$CFGNVIDIA"
fi
pkexec sh -c 'echo -n "$0" >> /tmp/os-installer/etc/nixos/configuration.nix' "$CFGNETWORK"
pkexec sh -c 'echo -n "$0" >> /tmp/os-installer/etc/nixos/configuration.nix' "$CFGTIME"
pkexec sh -c 'echo -n "$0" >> /tmp/os-installer/etc/nixos/configuration.nix' "$CFGLOCALE"
if [[ $OSI_LOCALE != $OSI_FORMATS ]]
then
    pkexec sh -c 'echo -n "$0" >> /tmp/os-installer/etc/nixos/configuration.nix' "$CFGLOCALEEXTRAS"
fi
pkexec sh -c 'echo -n "$0" >> /tmp/os-installer/etc/nixos/configuration.nix' "$CFGKEYMAP"
pkexec sh -c 'echo -n "$0" >> /tmp/os-installer/etc/nixos/configuration.nix' "$CFGGNOME"
pkexec sh -c 'echo -n "$0" >> /tmp/os-installer/etc/nixos/configuration.nix' "$CFGMISC"
pkexec sh -c 'echo -n "$0" >> /tmp/os-installer/etc/nixos/configuration.nix' "$CFGUSERS"
if [[ $OSI_USER_AUTOLOGIN == 1 ]]
then
    pkexec sh -c 'echo -n "$0" >> /tmp/os-installer/etc/nixos/configuration.nix' "$CFGAUTOLOGIN"
    pkexec sh -c 'echo -n "$0" >> /tmp/os-installer/etc/nixos/configuration.nix' "$CFGAUTOLOGINGDM"
fi
pkexec sh -c 'echo -n "$0" >> /tmp/os-installer/etc/nixos/configuration.nix' "$CFGUNFREE"
if [[ $INTELPRIME == 1 || $AMDPRIME == 1 ]]
then
  pkexec sh -c 'echo -n "$0" >> /tmp/os-installer/etc/nixos/configuration.nix' "$CFGPKGSPRIME"
else
  pkexec sh -c 'echo -n "$0" >> /tmp/os-installer/etc/nixos/configuration.nix' "$CFGPKGS"
fi
pkexec sh -c 'echo -n "$0" >> /tmp/os-installer/etc/nixos/configuration.nix' "$CFGTAIL"

# Install SnowflakeOS
pkexec nixos-install --root /tmp/os-installer --no-root-passwd --no-channel-copy --flake /tmp/os-installer/etc/nixos#snowflakeos

echo ${USERNAME:1:-1}:$OSI_USER_PASSWORD | pkexec nixos-enter --root /tmp/os-installer -c chpasswd

echo
echo 'Configuration completed.'

exit 0
