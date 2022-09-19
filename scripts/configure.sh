#! /bin/sh

# This is an example configuration script. For OS-Installer to use it, place it at:
# /etc/os-installer/scripts/configure.sh
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
echo 'OSI_USER_PASSWORD        ' $OSI_USER_PASSWORD
echo 'OSI_FORMATS              ' $OSI_FORMATS
echo 'OSI_TIMEZONE             ' $OSI_TIMEZONE
echo 'OSI_ADDITIONAL_SOFTWARE  ' $OSI_ADDITIONAL_SOFTWARE
echo ''

NIXOSVER=$(nixos-version | head -c 5)

# USE echo -n

FLAKETXT="""{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    snowflake = {
      url = "github:snowflakelinux/snowflake-modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, snowflake, ... }@inputs:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.snowflakeos = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./configuration.nix
          ./snowflake.nix
          snowflake.nixosModules.snowflake
        ];
        specialArgs = { inherit inputs; inherit system; };
    };
  };
}
"""

SNOWFLAKETXT="""{ config, pkgs, inputs, system, ... }:

{
  snowflakeos.gnome.enable = true;
  snowflakeos.osInfo.enable = true;
}
"""

CFGHEAD="""# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

"""
CFGBOOTEFI="""  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot/efi";

"""

CFGBOOTBIOS="""  # Bootloader.
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "@@bootdev@@";
  boot.loader.grub.useOSProber = true;

"""

CFGBOOTCRYPT="""  # Setup keyfile
  boot.initrd.secrets = {
    "/crypto_keyfile.bin" = null;
  };

"""

CFGBOOTGRUBCRYPT="""  # Enable grub cryptodisk
  boot.loader.grub.enableCryptodisk=true;

"""

CFGSWAPCRYPT="""  # Enable swap on luks
  boot.initrd.luks.devices."@@swapdev@@".device = "/dev/disk/by-uuid/@@swapuuid@@";
  boot.initrd.luks.devices."@@swapdev@@".keyFile = "/crypto_keyfile.bin";

"""

CFGNETWORK="""  networking.hostName = "snowflakeos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

"""

CFGTIME="""  # Set your time zone.
  time.timeZone = "$OSI_TIMEZONE";

"""

CFGLOCALE="""  # Select internationalisation properties.
  i18n.defaultLocale = "$OSI_LOCALE";

"""

CFGLOCALEEXTRAS="""  i18n.extraLocaleSettings = {
    LC_ADDRESS = "$OSI_FORMATS";
    LC_IDENTIFICATION = "$OSI_FORMATS";
    LC_MEASUREMENT = "$OSI_FORMATS";
    LC_MONETARY = "$OSI_FORMATS";
    LC_NAME = "$OSI_FORMATS";
    LC_NUMERIC = "$OSI_FORMATS";
    LC_PAPER = "$OSI_FORMATS";
    LC_TELEPHONE = "$OSI_FORMATS";
    LC_TIME = "$OSI_FORMATS";
  };

"""

CFGGNOME="""  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

"""

CFGKEYMAP="""  # Configure keymap in X11
  services.xserver = {
    layout = "us";
    xkbVariant = "";
  };

"""
CFGCONSOLE="""  # Configure console keymap
  console.keyMap = "";

"""

CFGMISC="""  # Enable CUPS to print documents.
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
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

"""

CFGUSERS="""  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.$OSI_USER_NAME = {
    isNormalUser = true;
    description = "$OSI_USER_NAME";
    extraGroups = [ "wheel" "networkmanager" "dialout" ];;
  };

"""

CFGAUTOLOGIN="""  # Enable automatic login for the user.
  services.xserver.displayManager.autoLogin.enable = true;
  services.xserver.displayManager.autoLogin.user = "$OSI_USER_NAME";

"""

CFGAUTOLOGINGDM="""  # Workaround for GNOME autologin: https://github.com/NixOS/nixpkgs/issues/103746#issuecomment-945091229
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

"""

CFGUNFREE="""  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

"""

CFGPKGS="""  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
  #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #  wget
    firefox
  ];

"""

CFGTAIL="""  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "$NIXOSVER"; # Did you read the comment?

}
"""

sleep 1

# Create flake.nix
pkexec sh =c "echo -n \"$FLAKETXT\" > /tmp/os-installer/etc/nixos/flake.nix"

# Create snowflake.nix
pkexec sh -c "echo -n \"$SNOWFLAKETXT\" > /tmp/os-installer/etc/nixos/snowflake.nix"

# Create configuration.nix
pkexec echo -n "$CFGHEAD" > /tmp/os-installer/etc/nixos/configuration.nix
pkexec echo -n "$CFGBOOTEFI" >> /tmp/os-installer/etc/nixos/configuration.nix
pkexec echo -n "$CFGNETWORK" >> /tmp/os-installer/etc/nixos/configuration.nix
pkexec echo -n "$CFGTIME" >> /tmp/os-installer/etc/nixos/configuration.nix
pkexec echo -n "$CFGLOCALE" >> /tmp/os-installer/etc/nixos/configuration.nix
if [[ $OSI_LOCALE != OSI_FORMATS ]]
then
    pkexec echo -n "$CFGLOCALEEXTRAS" >> /tmp/os-installer/etc/nixos/configuration.nix
fi
pkexec echo -n "$CFGGNOME" >> /tmp/os-installer/etc/nixos/configuration.nix
pkexec echo -n "$CFGMISC" >> /tmp/os-installer/etc/nixos/configuration.nix
pkexec echo -n "$CFGUSERS" >> /tmp/os-installer/etc/nixos/configuration.nix
if [[ $OSI_AUTOLOGIN == 1 ]]
then
    pkexec echo -n "$CFGAUTOLOGIN" >> /tmp/os-installer/etc/nixos/configuration.nix
    pkexec echo -n "$CFGAUTOLOGINGDM" >> /tmp/os-installer/etc/nixos/configuration.nix
fi
pkexec echo -n "$CFGUNFREE" >> /tmp/os-installer/etc/nixos/configuration.nix
pkexec echo -n "$CFGPKGS" >> /tmp/os-installer/etc/nixos/configuration.nix
pkexec echo -n "$CFGTAIL" >> /tmp/os-installer/etc/nixos/configuration.nix

# Install SnowflakeOS
pkexec nixos-install --root /tmp/os-installer --no-root-passwd --no-channel-copy --flake /tmp/os-installer/etc/nixos#snowflakeos

echo
echo 'Configuration completed.'

while true
do
    sleep 1
done

exit 0