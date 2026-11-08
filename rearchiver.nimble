from std/strformat import `&`

version       = "0.2.1"
author        = "Kirill I"
description   = "Prepare your Reaper project for archiving, converting WAV to FLAC and changing the RPP file accordingly"
license       = "GPL-3.0-or-later"
srcDir        = "src"
bin           = @["rearchiver"]


# Dependencies

requires "nim >= 2.2.10", "threading >= 0.2.1"
requires "cozytaskpool == 0.1.2"
requires "cozylogwriter == 0.1.0"
requires "cozycliparser == 0.3.3"
requires "https://github.com/indiscipline/cozywavparser#b118b5c"

task test, "Build and run integration tests":
  exec "nimble build -y"
  exec "nim r tests/test_integration.nim"

task release, "Build release":
  let binName = bin[0] & (when defined(windows): ".exe" else: "")
  exec(&"nim c --define:release --out:{binName} src/{bin[0]}.nim")
