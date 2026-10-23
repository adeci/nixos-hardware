{
  lib,
  kernel,
  kernelModuleMakeFlags,
  pname,
  # Source directory of the module inside the kernel tree.
  dir,
  # Module name without .ko, and the objects it links, as in dir/Makefile.
  module,
  objects,
  patches,
  description,
}:

# Rebuilds a single in-tree module from the running kernel's own source with
# patches on top, so a one-file driver fix does not recompile the kernel. It
# installs under updates/, which depmod searches before kernel/, so the
# patched module replaces the stock one under the same name.
kernel.stdenv.mkDerivation {
  inherit pname patches;
  version = kernel.version;
  src = kernel.src;

  nativeBuildInputs = kernel.moduleBuildDependencies;
  hardeningDisable = [
    "pic"
    "format"
  ];
  enableParallelBuilding = true;
  patchFlags = [
    "-p1"
    "--fuzz=0"
  ];

  unpackPhase = ''
    runHook preUnpack
    mkdir source
    cd source
    tar -xf "$src" --strip-components=1 --wildcards '*/${dir}/*'
    runHook postUnpack
  '';

  # A directory's Makefile builds every module the kernel config enables
  # there (all of sound/soc/codecs, say); build only this one.
  buildPhase = ''
    runHook preBuild
    cat > ${dir}/Makefile <<'EOF'
    obj-m += ${module}.o
    ${module}-y := ${lib.concatStringsSep " " objects}
    EOF
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      ${lib.escapeShellArgs kernelModuleMakeFlags} \
      M="$PWD/${dir}" -j"$NIX_BUILD_CORES" modules
    runHook postBuild
  '';

  # modules_install signs the module (nixpkgs writes a .ko.cer beside it),
  # which the kernel's module aggregation requires.
  installPhase = ''
    runHook preInstall
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      ${lib.escapeShellArgs kernelModuleMakeFlags} \
      M="$PWD/${dir}" INSTALL_MOD_PATH=$out INSTALL_MOD_DIR=updates DEPMOD=true \
      modules_install
    runHook postInstall
  '';

  # Kbuild already produced the final module.
  dontStrip = true;
  dontPatchELF = true;

  meta = {
    inherit description;
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
  };
}
