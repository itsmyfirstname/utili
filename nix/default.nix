# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  ## Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  ## Networking
  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  networking.networkmanager.enable = true;
  networking.firewall.allowedTCPPorts = [ 9000 ];

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
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

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users."mehays" = {
    isNormalUser = true;
    description = "mehays";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
    #  thunderbird
    ];
  };

  # Install firefox.
  programs.firefox.enable = true;
  programs.git.enable = true;
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
  #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #  wget
    uv
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.qemuGuest.enable = true;
  programs.nix-ld.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "26.05"; # Did you read the comment?

  # Allow proprietary packages like CUDA and Nvidia drivers
  nixpkgs.config.allowUnfree = true;

  # Enable Graphics
  hardware.graphics = {
    enable = true;
  };

  # Load the Nvidia driver
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    open = false; # Proprietary drivers are recommended for the best CUDA performance
    nvidiaSettings = true;
  };
  systemd.services.llama-server = let
    # Build llama-cpp explicitly with CUDA acceleration enabled
    llama-cpp-cuda = pkgs.llama-cpp.override { cudaSupport = true; };
    in {
      description = "llama.cpp server instance";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        # Added '-ngl 99' to force offloading all model layers to VRAM
        #ExecStart = "${llama-cpp-cuda}/bin/llama-server --models-dir /var/lib/models --no-models-autoload --jinja --host 0.0.0.0 --port 9000 -ngl 999 -c 32768";
        #ExecStart = "${llama-cpp-cuda}/bin/llama-server --models-dir /var/lib/models --no-models-autoload --jinja --host 0.0.0.0 --port 9000 -ngl 999 -c 131072 --cache-type-k q4_0 --cache-type-v q4_0 -fa";
        ExecStart = "${llama-cpp-cuda}/bin/llama-server -m /var/lib/models/Qwen3.8-27B-Q4_0.gguf --models-dir /var/lib/models --no-models-autoload --jinja --host 0.0.0.0 --port 9000 -ngl 999 -c 131072 --cache-type-k q4_0 --cache-type-v q4_0 -fa on -b 2048 -ub 512";
        Restart = "always";
        RestartSec = "5s";
      };
    };
  #systemd.services.llama-server = {
   # description = "llama.cpp server instance";
    #wantedBy = [ "multi-user.target" ];
    #after = [ "network.target" ];

    #serviceConfig = {
      # Replace pkgs.llama-cpp with your specific package/override if you use a custom CUDA build in your nix-shell
     # ExecStart = "${pkgs.llama-cpp}/bin/llama-server --model /var/lib/models/Qwen3-Coder-30B-A3B-Instruct-UD-Q4_K_XL.gguf --host 0.0.0.0 --port 9000";
      #Restart = "always";
      #RestartSec = "5s";
      # Optional but recommended: run as your standard user instead of root
      # User = "yourusername";
    #};
  #};
}
