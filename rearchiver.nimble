from std/strformat import `&`

version       = "0.1.0"
author        = "Kirill I"
description   = "Prepare your Reaper project for archiving, converting WAV to FLAC and changing the RPP file accordingly"
license       = "GPL-3.0-or-later"
srcDir        = "src"
bin           = @["rearchiver"]


# Dependencies

requires "nim >= 1.6.6", "argparse >= 3.0.0", "fusion >= 1.1", "threading >= 0.1.0"

task release, "Build release":
  let binName = bin[0] & (when defined(windows): ".exe" else: "")
  exec(&"nim c --define:release --out:{binName} src/{bin[0]}.nim")
