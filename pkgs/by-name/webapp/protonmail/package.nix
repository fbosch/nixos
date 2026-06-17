{ pkgs }:

(import ../helium-webapps.nix { inherit pkgs; }).mkHeliumApp {
  appName = "protonmail";
  categories = [
    "Network"
    "Email"
  ];
  desktopName = "Proton Mail";
  wmClass = "Proton Mail";
  comment = "Secure encrypted email";
  faviconHash = "sha256-IkLdXUeULtu3J8R9yQS8hbj4ZofhvG2uLW1/oDJSw5U=";
  profile = "ProtonmailProfile";
  url = "https://mail.proton.me";
  runtime.extraFlags = [
    "--hide-scrollbars"
    "--site-per-process"
    "--isolate-origins=https://mail.proton.me"
  ];
}
