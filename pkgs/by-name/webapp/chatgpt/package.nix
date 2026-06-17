{ pkgs }:

(import ../helium-webapps.nix { inherit pkgs; }).mkHeliumApp {
  appName = "chatgpt";
  categories = [
    "Office"
    "Utility"
  ];
  desktopName = "ChatGPT";
  wmClass = "ChatGPT";
  comment = "AI-powered conversational assistant by OpenAI";
  icon = ./chatgpt.png;
  faviconHash = "sha256-NzyhPg9H5mrfs1bpldEE1sgJ4VxLpIu5ptuZGlexiaY=";
  profile = "ChatGPTProfile";
  url = "https://chat.openai.com";
  runtime = {
    extraFlags = [
      "--hide-scrollbars"
      "--disable-background-timer-throttling"
    ];
    policyOverrides = {
      DefaultNotificationsSetting = 1;
      DefaultPopupsSetting = 1;
    };
  };
}
