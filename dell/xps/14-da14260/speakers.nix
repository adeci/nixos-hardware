{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    mkIf
    mkOption
    types
    versionAtLeast
    ;
  cfg = config.hardware.dell-xps-14-da14260;
  kernelPackages = config.boot.kernelPackages;
in
{
  options.hardware.dell-xps-14-da14260.speakerId = mkOption {
    type = types.nullOr types.ints.unsigned;
    default = 0;
    description = ''
      Speaker ID the four CS35L57 amplifiers use to pick their tuning
      (`cs35l57-b2-dsp1-misc-10280db9-spkid<N>-*.bin`), or null to detect it
      from the speaker-ID GPIO as the stock driver does. Kernel >= 7.2 only.

      Detection is unreliable on this board. The GPIO (GPI1 pin 20) is also the
      Intel CVS camera bridge's wake line, and the running bridge drives it low
      hard enough to beat a 5 kΩ pull-up, so every unit reads 0 -- except the
      odd amplifier that probes while intel_cvs restarts the bridge, which can
      read 1 and load another speaker's tuning. With the bridge held in reset,
      the line follows a board pull-down, so 0 is also what the board says.
    '';
  };

  # ACPI lists GPI1 pin 20 as both the CVS wake input and the speaker-ID input
  # that all four amplifiers read at probe. The in-tree intel_cvs claims it, so
  # every amplifier fails with -EBUSY ("Failed to get spk-id-gpios") and no
  # sound card registers. The CVS patch takes the wake IRQ without claiming the
  # line (Omarchy's linux-omarchy 0542). The CS35L56 patches serialize the
  # amplifiers' exclusive requests for the shared line, which otherwise race at
  # boot (Peter Petrov's XPS 14), and add the speaker_id parameter behind the
  # option above. None of this is upstream yet. Both modules are rebuilt from
  # the kernel's own source, so the kernel itself is not recompiled, and fail
  # to build if that source drifts. No clash with irCamera's intel_cvs: that
  # option requires 7.1.
  config = mkIf (versionAtLeast kernelPackages.kernel.version "7.2") {
    boot.extraModulePackages = [
      (kernelPackages.callPackage ./in-tree-module.nix {
        pname = "intel-cvs-wake-irq";
        dir = "drivers/media/i2c/cvs";
        module = "intel_cvs";
        objects = [
          "core.o"
          "v4l2.o"
        ];
        patches = [ ./cvs-wake-irq.patch ];
        description = "In-tree intel_cvs taking its wake IRQ without claiming the GPIO";
      })
      (kernelPackages.callPackage ./in-tree-module.nix {
        pname = "cs35l56-spk-id";
        dir = "sound/soc/codecs";
        module = "snd-soc-cs35l56-shared";
        objects = [ "cs35l56-shared.o" ];
        patches = [
          ./cs35l56-spk-id.patch
          ./cs35l56-spk-id-param.patch
        ];
        description = "CS35L56 shared module with serialized, overridable speaker-ID detection";
      })
    ];

    boot.extraModprobeConfig = mkIf (cfg.speakerId != null) ''
      options snd_soc_cs35l56_shared speaker_id=${toString cfg.speakerId}
    '';
  };
}
