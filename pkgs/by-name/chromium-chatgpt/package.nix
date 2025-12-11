{ pkgs }:

pkgs.nix-webapps-lib.mkChromiumApp {
  appName = "chromium-chatgpt";
  categories = [ "Office" "Utility" ];
  class = "chromium-chatgpt";
  desktopName = "ChatGPT";
  comment = "AI-powered conversational assistant by OpenAI";
  icon = ./chatgpt.png;
  profile = "ChatGPTProfile";
  url = "https://chat.openai.com";
  hardening = {
    extraFlags = [ "--hide-scrollbars" ];
    policyOverrides = {
      # Allow notifications for ChatGPT (may be needed for responses)
      DefaultNotificationsSetting = 1;
    };
  };
}
