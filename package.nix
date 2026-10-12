{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  versionCheckHook,
  bubblewrap,
  git,
}:

let
  sources = lib.importJSON ./sources.json;
  inherit (stdenv.hostPlatform) system;
  source =
    sources.platforms.${system} or (throw "muse-code: Meta does not publish a binary for ${system}");
in
stdenv.mkDerivation {
  pname = "muse-code";
  inherit (sources) version;

  src = fetchurl {
    # The URL's basename is a query string, which is not a valid store path name.
    # Must match the --name used by scripts/update.sh so prefetched paths are reused.
    name = "muse-${sources.version}-${system}";
    inherit (source) url hash;
  };

  dontUnpack = true;

  # The binary is fully static (no PT_INTERP, no DT_NEEDED), so there is nothing
  # for autoPatchelfHook to do. Keep it byte-identical to Meta's checksum: the
  # sandbox helper re-executes /proc/self/exe and checks its own image identity.
  dontStrip = true;
  dontPatchELF = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/bin/muse
    # bwrap: the Linux sandbox looks for a capability-valid bwrap on PATH and
    #   refuses to run tools without one.
    # git: used for worktrees and repo inspection; the user's own git wins.
    # MUSE_NO_AUTO_UPDATE: self-update lives only in Meta's bash launcher, which
    #   is not shipped here; set its opt-out anyway in case the binary adopts it.
    wrapProgram $out/bin/muse \
      --prefix PATH : ${lib.makeBinPath [ bubblewrap ]} \
      --suffix PATH : ${lib.makeBinPath [ git ]} \
      --set MUSE_NO_AUTO_UPDATE 1

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  meta = {
    description = "Meta's Muse Code terminal coding agent (unofficial repackaging)";
    homepage = "https://dev.meta.ai/docs/muse-code";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "muse";
    platforms = builtins.attrNames sources.platforms;
  };
}
