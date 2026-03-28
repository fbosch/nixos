{ pkgs }:

pkgs.nix-webapps-lib.mkChromiumApp {
  appName = "chromium-protonmail";
  categories = [
    "Network"
    "Email"
  ];
  class = "Proton Mail";
  desktopName = "Proton Mail";
  comment = "Secure encrypted email";
  icon = ./proton-mail-seeklogo.svg;
  profile = "ProtonmailProfile";
  url = "https://mail.proton.me";
  hardening = {
    extraFlags = [
      "--hide-scrollbars"
      "--site-per-process"
      "--isolate-origins=https://mail.proton.me"
    ];
  };
}
