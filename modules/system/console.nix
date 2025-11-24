{
  flake.modules.nixos.system = {
    console.font = "Lat2-Terminus16";

    console.colors = [
      # Standard colors (0-7)
      "000000" # 0: black (background)
      "d86659" # 1: red (rose)
      "7aca6c" # 2: green (leaf)
      "c69761" # 3: yellow (wood)
      "5b64db" # 4: blue (water)
      "b671a1" # 5: magenta (blossom)
      "6baedb" # 6: cyan (sky)
      "bbbdc7" # 7: white (foreground - stone)
      # Bright colors (8-15) - brighter versions
      "2a2a2a" # 8: bright black (darker gray)
      "e58073" # 9: bright red (brighter rose)
      "8ada7c" # 10: bright green (brighter leaf)
      "d6a771" # 11: bright yellow (brighter wood)
      "6b74eb" # 12: bright blue (brighter water)
      "c681b1" # 13: bright magenta (brighter blossom)
      "7bbefb" # 14: bright cyan (brighter sky)
      "cbcbd5" # 15: bright white (brighter stone)
    ];
  };
}
