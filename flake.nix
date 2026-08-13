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

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
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
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              quickshell # qs — the runtime; `qs -p shell.qml`
              hyprland # hyprctl — scripts/check.sh probes it; night light IPC
              matugen # regenerate the palette JSON while testing theming
              brightnessctl # Brightness.qml backend
              libnotify # notify-send paths in SystemTools.qml
              inotify-tools # Screenshot.qml's file watcher
              shellcheck # for edits under scripts/
            ];

            shellHook = ''
              echo "silere-shell dev shell"
              echo "  run:    qs -p shell.qml   (needs a running Wayland compositor)"
              echo "  gates:  bash scripts/ci-lint.sh && bash scripts/check.sh"
            '';
          };
        }
      );
    };
}
