import std/[os, osproc, streams, strutils, unittest]

const
  ValidWavs = [
    "bext-before-fmt-padded.wav",
    "fllr-after-fmt.wav",
    "canonical-pcm16.wav",
  ]
  BrokenWavs = ["broken.wav", "invalid-fmt.wav"]
  FloatWav = "float32.wav"

func rppFor(files: openArray[string]): string =
  result = "<REAPER_PROJECT 0.1 \"7.0\" 1\n"
  for file in files:
    result.add "  <ITEM\n    <SOURCE WAVE\n      FILE \"" & file &
      "\"\n    >\n  >\n"
  result.add ">\n"

proc binaryPath(): string =
  getCurrentDir() / ("rearchiver" & ExeExt)

func normalized(s: string): string =
  s.splitWhitespace.join(" ")

func hasTaggedLine(output, tag, needle: string): bool =
  for line in output.splitLines:
    if line.strip.startsWith(tag) and line.contains(needle):
      return true

template requireTool(name: string; body: untyped) =
  if findExe(name) == "":
    if getEnv("CI") != "":
      check false
    else:
      skip()
  else:
    body

proc runRearchiver(workingDir: string;
                   args: openArray[string]): tuple[output: string, code: int] =
  let process = startProcess(
    binaryPath(),
    workingDir = workingDir,
    args = args,
    options = {poUsePath, poStdErrToStdOut})
  result.output = process.outputStream.readAll()
  result.code = process.waitForExit()
  process.close()

proc newTempDir(label: string): string =
  result = getTempDir() / ("rearchiver-test-" & label & "-" & $getCurrentProcessId())
  if dirExists(result):
    removeDir(result)
  createDir(result)

proc copyWavs(dir: string; wavs: openArray[string]) =
  let wavDir = getCurrentDir() / "tests" / "wavs"
  for wav in wavs:
    copyFile(wavDir / wav, dir / wav)

proc writeProject(dir: string; wavs: openArray[string]) =
  writeFile(dir / "test.rpp", rppFor(wavs))

suite "rearchiver integration":
  test "version and help":
    check fileExists(binaryPath())
    let (version, versionCode) = runRearchiver(getCurrentDir(), ["--version"])
    check versionCode == 0
    check version.contains("rearchiver")

    let (help, helpCode) = runRearchiver(getCurrentDir(), ["-h"])
    check helpCode == 0
    check help.contains("Usage: rearchiver")

  test "valid BWF converts, broken files are culled":
    requireTool("flac"):
      let tempDir = newTempDir("convert")
      defer: removeDir(tempDir)
      let allWavs = @ValidWavs & @BrokenWavs
      copyWavs(tempDir, allWavs)
      writeProject(tempDir, allWavs)

      let (output, code) = runRearchiver(
        tempDir, ["-y", "-o", "out.rpp", "test.rpp"])

      # Failed conversions are culled from the project but do not fail the run.
      check code == 0

      for wav in ValidWavs:
        check not hasTaggedLine(output, "[WARN]", wav)
        check not hasTaggedLine(output, "[ERR]", wav)
        check hasTaggedLine(output, "[LOG]", wav.changeFileExt(".flac"))
        check fileExists(tempDir / wav.changeFileExt(".flac"))

      for wav in BrokenWavs:
        check hasTaggedLine(output, "[WARN]", "Error reading '" & wav & "'")
        check hasTaggedLine(output, "[ERR]", wav.changeFileExt(".flac"))
        check not fileExists(tempDir / wav.changeFileExt(".flac"))

      let outputRpp = readFile(tempDir / "out.rpp").normalized
      for wav in ValidWavs:
        check outputRpp.contains(
          "SOURCE FLAC FILE \"" & wav.changeFileExt(".flac") & "\"")
      for wav in BrokenWavs:
        check outputRpp.contains("SOURCE WAVE FILE \"" & wav & "\"")

      for wav in ValidWavs:
        let (_, flacCode) = execCmdEx(
          "flac -t " & quoteShell(tempDir / wav.changeFileExt(".flac")),
          options = {poUsePath, poStdErrToStdOut})
        check flacCode == 0

  test "default output suffix":
    requireTool("flac"):
      let tempDir = newTempDir("suffix")
      defer: removeDir(tempDir)
      copyWavs(tempDir, ["canonical-pcm16.wav"])
      writeProject(tempDir, ["canonical-pcm16.wav"])

      let (output, code) = runRearchiver(tempDir, ["-y", "test.rpp"])
      check code == 0
      check hasTaggedLine(output, "[LOG]", "canonical-pcm16.flac")
      check fileExists(tempDir / "test_archived.rpp")
      check not fileExists(tempDir / "out.rpp")
      check readFile(tempDir / "test_archived.rpp").normalized.contains(
        "SOURCE FLAC FILE \"canonical-pcm16.flac\"")

  test "stdout output":
    requireTool("flac"):
      let tempDir = newTempDir("stdout")
      defer: removeDir(tempDir)
      copyWavs(tempDir, ["canonical-pcm16.wav"])
      writeProject(tempDir, ["canonical-pcm16.wav"])

      let (output, code) = runRearchiver(
        tempDir, ["-y", "-o", "-", "test.rpp"])
      check code == 0
      check output.normalized.contains("<REAPER_PROJECT 0.1 \"7.0\" 1")
      check output.normalized.contains(
        "SOURCE FLAC FILE \"canonical-pcm16.flac\"")
      check not fileExists(tempDir / "test_archived.rpp")
      check not fileExists(tempDir / "out.rpp")

  test "cleanup removes converted sources only":
    requireTool("flac"):
      let tempDir = newTempDir("cleanup")
      defer: removeDir(tempDir)
      let wavs = ["canonical-pcm16.wav", "broken.wav"]
      copyWavs(tempDir, wavs)
      writeProject(tempDir, wavs)
      writeFile(tempDir / "canonical-pcm16.wav.reapeaks", "stale")

      let (output, code) = runRearchiver(
        tempDir, ["-x", "-y", "-o", "out.rpp", "test.rpp"])
      check code == 0
      check hasTaggedLine(output, "[LOG]", "canonical-pcm16.flac")
      check fileExists(tempDir / "canonical-pcm16.flac")
      check not fileExists(tempDir / "canonical-pcm16.wav")
      check not fileExists(tempDir / "canonical-pcm16.wav.reapeaks")
      check fileExists(tempDir / "broken.wav")

  test "float WAV selects WavPack":
    requireTool("wavpack"):
      let tempDir = newTempDir("wavpack")
      defer: removeDir(tempDir)
      copyWavs(tempDir, [FloatWav])
      writeProject(tempDir, [FloatWav])

      let (output, code) = runRearchiver(
        tempDir, ["-y", "-o", "out.rpp", "test.rpp"])
      check code == 0
      check not hasTaggedLine(output, "[WARN]", FloatWav)
      check hasTaggedLine(output, "[LOG]", FloatWav.changeFileExt(".wv"))
      check fileExists(tempDir / FloatWav.changeFileExt(".wv"))
      check readFile(tempDir / "out.rpp").normalized.contains(
        "SOURCE WAVPACK FILE \"float32.wv\"")

      if findExe("wvunpack") != "":
        let (_, unpackCode) = execCmdEx(
          "wvunpack -v " & quoteShell(tempDir / FloatWav.changeFileExt(".wv")),
          options = {poUsePath, poStdErrToStdOut})
        check unpackCode == 0
      elif getEnv("CI") != "":
        check false
