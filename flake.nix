{
  description = "cilantro.nvim - file-based task/event manager for Neovim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      overlays.default = final: prev: {
        vimPlugins = prev.vimPlugins // {
          cilantro-nvim = self.packages.${final.system}.default;
        };
      };

      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.vimUtils.buildVimPlugin {
            pname = "cilantro-nvim";
            version = self.shortRev or self.dirtyShortRev or "dev";
            src = self;
          };
        }
      );
    };
}
