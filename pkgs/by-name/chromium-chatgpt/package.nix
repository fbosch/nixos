{ pkgs }:

pkgs.nix-webapps-lib.mkChromiumApp {
  appName = "chromium-chatgpt";
  categories = [
    "Office"
    "Utility"
  ];
  class = "ChatGPT";
  desktopName = "ChatGPT";
  comment = "AI-powered conversational assistant by OpenAI";
  icon = ./chatgpt.png;
  profile = "ChatGPTProfile";
  url = "https://chat.openai.com";
  hardening = {
    extraFlags = [
      "--hide-scrollbars"
      # ChatGPT-specific optimizations
      "--disable-background-timer-throttling" # Keep ChatGPT responsive
    ];
    policyOverrides = {
      # Allow notifications for ChatGPT (may be needed for responses)
      DefaultNotificationsSetting = 1;
      # Allow popups so external links can open in new windows/browser
      DefaultPopupsSetting = 1; # 1 = Allow, 2 = Block
    };
  };
}
