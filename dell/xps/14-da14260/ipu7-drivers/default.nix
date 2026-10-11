{
  stdenv,
  lib,
  kernel,
  fetchFromGitHub,
}:

# Kernels >= 6.17 ship an IPU7 core and ISys in drivers/staging/media/ipu7,
# but no PSys, so they cannot drive the hardware ISP that the camera HAL
# needs. This package supplies just the PSys module (intel-ipu7-psys), which
# has no in-tree counterpart, and links it against the in-tree core and ISys
# that already enumerate the sensor.
#
# Vendored from nixpkgs PR #542085; drop once that merges and use
# config.boot.kernelPackages.ipu7-drivers instead.
stdenv.mkDerivation {
  name = "ipu7-drivers-${kernel.version}";

  src = fetchFromGitHub {
    owner = "intel";
    repo = "ipu7-drivers";
    rev = "495acc90feb09d8008c0a6228fb8bb4c6415ca62";
    hash = "sha256-a2hIJ4wMCHQeDb4gp+5pjLizJ/CCfA0JivVDWeqB4vY=";
  };

  # The repo carries its own copy of the core's headers, and since 0e8c71a its
  # struct ipu7_bus_device has two fields the in-tree core never allocates.
  # PSys probe wrote one of them past the 1008-byte struct into the next slab
  # object, which crashed about one reboot in three in device_shutdown (list_del
  # corruption). Compile against the running kernel's staging headers instead,
  # and drop the code using those fields: it pairs with the out-of-tree MMU
  # code, which is not loaded alongside the in-tree core. From andreas705 on
  # nixos-hardware#1912, verified clean with slub_debug.
  patches = [ ./in-tree-abi.patch ];

  postPatch = ''
    tar -xf ${kernel.src} --strip-components=5 -C drivers/media/pci/intel/ipu7 \
      --wildcards '*/drivers/staging/media/ipu7/*.h'
  '';

  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags = [
    "KERNELRELEASE=${kernel.modDirVersion}"
    "KERNEL_SRC=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
  ];

  enableParallelBuilding = true;

  preInstall = ''
    substituteInPlace Makefile \
      --replace-fail "INSTALL_MOD_DIR=" "INSTALL_MOD_PATH=$out INSTALL_MOD_DIR="
  '';

  installTargets = [ "modules_install" ];

  meta = {
    homepage = "https://github.com/intel/ipu7-drivers";
    description = "Intel IPU7 PSys kernel driver";
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
  };
}
