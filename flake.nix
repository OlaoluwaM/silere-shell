{
  # Development-only flake. It exposes a shell with the tools needed to hack on
  # silere-shell from any Nix-capable host (including non-NixOS ones): the
  # Quickshell runtime, the compositor CLI the scripts probe for, and the
  # optional tools the shell shells out to.
  #
  # Deliberately NOT a packaging flake: the NixOS configuration that deploys
  # this fork consumes the repository as a plain source input (flake = false)
  # and does its own packaging, because the build-time GeneratedDefaults.qml
  # substitution needs configuration knowledge only that consumer has. Keep it
  # that way — add no packages/overlays outputs here.
  description = "Dev shell for hacking on silere-shell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    quickshell = {
      url = "git+https://git.outfoxxed.me/quickshell/quickshell.git?ref=refs/tags/v0.3.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, quickshell, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          quickshellPackage = quickshell.packages.${system}.default;
          jetbrainsMonoNerdFont = pkgs.nerd-fonts.jetbrains-mono;
          fontsConf = pkgs.makeFontsConf {
            fontDirectories = [ jetbrainsMonoNerdFont ];
          };
          qmlImportPath = "${quickshellPackage}/lib/qt-6/qml:${pkgs.qt6.qtdeclarative}/lib/qt-6/qml";
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              quickshellPackage # qs — v0.9.0 requires 0.3.1
              qt6.qtdeclarative # qmllint and qmlcachegen for the headless type-check
              fontconfig # fc-match validates layout text metrics
              jetbrainsMonoNerdFont # the shell's default UI font
              hyprland # hyprctl — scripts/check.sh probes it; night light IPC
              matugen # regenerate the palette JSON while testing theming
              brightnessctl # Brightness.qml backend
              libnotify # notify-send paths in SystemTools.qml
              dbus # isolated notification reload probes
              inotify-tools # Screenshot.qml's file watcher
              shellcheck # for edits under scripts/
            ];

            # Nix keeps qmlcachegen in Qt Declarative's libexec directory and
            # Quickshell's wrapper normally adds these module roots only to the
            # process it starts. The check scripts run the Qt tools directly.
            QML2_IMPORT_PATH = qmlImportPath;
            FONTCONFIG_FILE = fontsConf;
            SILERE_REQUIRE_QML_TOOLS = "1";

            shellHook = ''
              echo "silere-shell dev shell"
              echo "  run:    qs -p shell.qml   (needs a running Wayland compositor)"
              echo "  gates:  bash scripts/ci-lint.sh && bash scripts/check.sh   (strict validation)"
            '';
          };
        }
      );
    };
}
