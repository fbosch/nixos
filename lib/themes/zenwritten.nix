let
  # Zenbones palette role names: rose, leaf, wood, water, blossom, sky.
  # Hex values preserve this repo's existing Zenwritten console palette.
  base = {
    black = "000000";
    background = "191919";
    surface = "242424";
    rose = "d86659";
    leaf = "7aca6c";
    wood = "c69761";
    water = "5b64db";
    blossom = "b671a1";
    sky = "6baedb";
    stone = "bbbdc7";
  };

  bright = {
    black = "2a2a2a";
    rose = "e58073";
    leaf = "8ada7c";
    wood = "d6a771";
    water = "6b74eb";
    blossom = "c681b1";
    sky = "7bbefb";
    stone = "cbcbd5";
  };

  withHash = builtins.mapAttrs (_: value: "#${value}");
in
{
  inherit base bright;

  css = {
    base = withHash base;
    bright = withHash bright;
  };

  console = [
    base.black
    base.rose
    base.leaf
    base.wood
    base.water
    base.blossom
    base.sky
    base.stone
    bright.black
    bright.rose
    bright.leaf
    bright.wood
    bright.water
    bright.blossom
    bright.sky
    bright.stone
  ];
}
