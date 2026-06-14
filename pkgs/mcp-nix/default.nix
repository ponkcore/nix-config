{
  lib,
  stdenv,
  inputs,
}: let
  inherit (stdenv.hostPlatform) system;
  mcpPkgs = import inputs.mcp-nix.inputs.nixpkgs {inherit system;};
  inherit (mcpPkgs) python313;

  workspace = inputs.mcp-nix.inputs.uv2nix.lib.workspace.loadWorkspace {
    workspaceRoot = inputs.mcp-nix;
  };

  overlay = workspace.mkPyprojectOverlay {
    sourcePreference = "wheel";
  };

  pythonBase = mcpPkgs.callPackage inputs.mcp-nix.inputs.pyproject-nix.build.packages {
    python = python313;
  };

  pyixxOverlay = _final: prev: {
    pyixx = prev.pyixx.overrideAttrs (old: {
      nativeBuildInputs =
        (old.nativeBuildInputs or [])
        ++ [
          mcpPkgs.rustPlatform.cargoSetupHook
          mcpPkgs.rustPlatform.maturinBuildHook
          mcpPkgs.cargo
          mcpPkgs.rustc
        ];

      cargoDeps = mcpPkgs.rustPlatform.importCargoLock {
        lockFile = "${inputs.mcp-nix}/pyixx/Cargo.lock";
        outputHashes = {
          "libixx-0.0.0-git" = "sha256-15Y6isGV3x4wqqwOhHdHs26P6hF7XAfc6izJ/oA7yBA=";
        };
      };
    });
  };

  wasmtimeOverlay = _final: prev: {
    wasmtime = prev.wasmtime.overrideAttrs (old: {
      src = mcpPkgs.fetchurl {
        url = "https://files.pythonhosted.org/packages/01/bb/8f6dd6a213706a101c7c598609015648fbd82bd34455cabdec300c304d8c/wasmtime-40.0.0-py3-none-manylinux1_x86_64.whl";
        hash = "sha256-0a0b6YS+o/IyXmcli8nW0tRSDP28w7CudSyLSBfQISw=";
      };
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [mcpPkgs.autoPatchelfHook];
      buildInputs = (old.buildInputs or []) ++ [mcpPkgs.stdenv.cc.cc.lib];
    });
  };

  mcpNixOverlay = _final: prev: {
    mcp-nix = prev.mcp-nix.overrideAttrs (old: {
      postPatch =
        (old.postPatch or "")
        + ''
          substituteInPlace mcp_nix/models.py \
            --replace-fail '@field_validator("homepage", mode="before")' '@field_validator("description", "homepage", mode="before")'
        '';
    });
  };

  pythonSet = pythonBase.overrideScope (
    lib.composeManyExtensions [
      inputs.mcp-nix.inputs.pyproject-build-systems.overlays.default
      overlay
      pyixxOverlay
      wasmtimeOverlay
      mcpNixOverlay
    ]
  );
in
  pythonSet.mkVirtualEnv "mcp-nix" workspace.deps.default
