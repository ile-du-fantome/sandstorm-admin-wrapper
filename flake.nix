{
  description = "Nix flake for Sandstorm Admin Wrapper (SAW)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      # steamcmd is x86_64-linux only in nixpkgs
      systems = [ "x86_64-linux" ];

      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              config.allowUnfree = true;
            }
          )
        );
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          version = self.shortRev or self.dirtyShortRev or "dev";

          ruby = pkgs.ruby_4_0;

          gems = pkgs.bundlerEnv {
            name = "sandstorm-admin-wrapper-gems";
            gemdir = ./admin-interface;
            inherit ruby;
          };

          # Keep the source in the Nix store, assemble a writable runtime tree
          # on first run
          app = pkgs.stdenvNoCC.mkDerivation {
            pname = "sandstorm-admin-wrapper";
            inherit version;

            src = self;

            installPhase = ''
              runHook preInstall

              mkdir -p $out/share/sandstorm-admin-wrapper
              cp -a \
                admin-interface \
                config \
                extras \
                sandstorm-server \
                server-config \
                steamcmd \
                $out/share/sandstorm-admin-wrapper/

              runHook postInstall
            '';

            meta = {
              description = "Web-based administration wrapper for Insurgency: Sandstorm servers";
              homepage = "https://github.com/Joe-Klauza/sandstorm-admin-wrapper";
              license = pkgs.lib.licenses.gpl3Plus;
              platforms = pkgs.lib.platforms.linux;
            };
          };

          launcher = pkgs.writeShellScriptBin "saw" ''
            set -eu

            app="${app}/share/sandstorm-admin-wrapper"
            saw_root="''${SAW_ROOT:-''${XDG_DATA_HOME:-''${HOME}/.local/share}/sandstorm-admin-wrapper}"

            export PATH="${
              pkgs.lib.makeBinPath [
                pkgs.coreutils
                pkgs.steamcmd
                gems.wrappedRuby
              ]
            }:$PATH"

            # Keep configuration files outside the Nix store so they remain
            # editable
            mkdir -p \
              "$saw_root/admin-interface/config" \
              "$saw_root/admin-interface/log" \
              "$saw_root/config" \
              "$saw_root/server-config" \
              "$saw_root/sandstorm-server" \
              "$saw_root/steamcmd/installation" \
              "$saw_root/steamcmd/mod.io/common/254/metadata"

            link_path() {
              mkdir -p "$(dirname "$2")"
              ln -sfn "$1" "$2"
            }

            copy_path() {
              mkdir -p "$(dirname "$2")"
              rm -rf "$2"
              cp -r --no-preserve=mode "$1" "$2"
            }

            # Keep these in the writable runtime rather than the Nix store
            for path in \
              admin-interface/lib \
              admin-interface/ext \
              admin-interface/docroot
            do
              copy_path "$app/$path" "$saw_root/$path"
            done

            copy_path "$app/config/config.toml.sample" "$saw_root/config/config.toml.sample"

            # SAW looks for SteamCMD at this path instead of searching PATH
            link_path "${pkgs.steamcmd}/bin/steamcmd" "$saw_root/steamcmd/installation/steamcmd.sh"
            touch "$saw_root/steamcmd/mod.io/common/254/metadata/state.json"

            cd "$saw_root/admin-interface"

            # Keep the "restart wrapper" button working
            while true; do
              ${gems.wrappedRuby}/bin/ruby "$saw_root/admin-interface/lib/webapp.rb" "$@"
              code=$?
              [ "$code" -eq 2 ] || exit "$code"
            done
          '';

          saw = pkgs.symlinkJoin {
            pname = "sandstorm-admin-wrapper";
            inherit version;
            paths = [
              app
              launcher
            ];

            meta = app.meta // {
              mainProgram = "saw";
            };
          };
        in
        {
          default = saw;
          sandstorm-admin-wrapper = saw;

          # Exposed for development shell and debugging
          gems = gems;
        }
      );

      devShells = forAllSystems (
        pkgs:
        let
          ruby = pkgs.ruby_4_0;
          gems = pkgs.bundlerEnv {
            name = "sandstorm-admin-wrapper-gems";
            gemdir = ./admin-interface;
            inherit ruby;
          };
        in
        {
          default = pkgs.mkShell {
            packages = [
              gems
              gems.wrappedRuby
              pkgs.steamcmd
              pkgs.git
            ];

            # Set up steamcmd and stub state.json
            shellHook = ''
              mkdir -p steamcmd/installation steamcmd/mod.io/common/254/metadata
              ln -sfn ${pkgs.steamcmd}/bin/steamcmd steamcmd/installation/steamcmd.sh
              touch steamcmd/mod.io/common/254/metadata/state.json
            '';
          };
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
