{ inputs, pkgs }:

inputs.self.lib.mkChromiumApp pkgs {
  appName = "chromium-protonmail";
  categories = [ "Network" "Email" ];
  class = "chrome-mail.proton.me_-ProtonProfile";
  desktopName = "ProtonMail";
  icon = "./proton-mail-seeklogo.svg";
  profile = "ProtonmailProfile";
  url = "https://mail.proton.me";
}
