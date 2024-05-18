import std/[strutils, strformat, terminal, osproc, options, tables, tasks, enumerate, exitprocs, critbits]
import pkg/[argparse]
import threading/channels
import ../cozytaskpool/src/cozytaskpool, ../cozylogwriter/cozylogwriter, ../cozywavparser/cozywavparser
from std/os import splitFile, joinPath, getCurrentDir
from std/pathnorm import normalizePath

#{.experimental: "views".}

const
  ## Autodefined by Nimble. If built using pure nim, use git tag
  NimblePkgVersion {.strdefine.} = staticExec("git describe --tags HEAD").strip()
  HelpStr = "Rearchiver " & NimblePkgVersion & """

* Convert WAV files used in a Reaper project to FLAC/WAVPACK for archiving.
* Compressed files are placed in the directory of the original.
* The updated RPP file is written to stdout or to a filepath given (`-o`).
* Prints a tab-separated list of file pairs to convert, unless `-y` is used.

A WAV file needs to reside inside the project directory to be converted.
A FLAC binary by xiph.org accessible from your environment is required.
  flac settings used: "--best --keep-foreign-metadata"
A WAVPACK binary is used for 32/64 bit floating point files or for `--wv` mode.
  wavpack settings used: "-hh -t -x3"
Logs to STDERR. No guarantees."""
  SourceMarker = "<SOURCE WAVE"
  FileMarker = "FILE \""

type
  ChunkRec = object
    pre: Slice[Natural] # Chunk up to "<SOURCE "
    mid: Slice[Natural] # Chunk from after "WAVE" up to end of "FILE \""
    name: string # Value of FILE
  Associative[T, U] = concept t, var u
    t[T] is U
    u.excl(T)
    u.hasKey(T) is bool
    t.pairs is (T, U)
  CodecStr = tuple[bin, ext, mark: string]
  Codec = enum CWav, CFlac, CWavpack

const
  CodecStrs: array[Codec, CodecStr] = [
      (bin: "", ext: ".wav", mark: "WAVE"),
      (bin: "flac", ext: ".flac", mark: "FLAC"),
      (bin: "wavpack", ext: ".wv", mark: "WAVPACK"),
    ]

#[------- Utils -------]#
func isAbsolute(path: string): bool =
  ## Force windows paths to be considered absolute on linux
  (path.len > 1 and path[0] in {'a'..'z', 'A'..'Z'} and path[1] == ':') or
  os.isAbsolute(path)

func normalizePathUniform(path: string): string =
  var normPath = path.normalizePath() # changes DirSep to match build's OS
  # Capitalize Windows drive letter if present
  if normPath.len >= 2 and normPath[1] == ':' and normPath[0] in {'a'..'z'}:
    normPath[0] = normPath[0].toUpperAscii()
  normPath

func childPathTail(path, subpath: string): Option[string] =
  ## If subpath is a child of an absolute path `path`, return the relative tail
  runnableExamples:
    assert childPathTail("c:/Users/bob", "C:/Users/bob/") == some("") # Drive case and trailing sep
    assert childPathTail("C:/Users/bob", "C:/Users/bob/Docs").get == "Docs"
    assert childPathTail("C:/Users/bob/Docs", "C:/Users/bob").isNone
    assert childPathTail("/home/bob/projects", "/home/bob/projects/foo/main.nim").get == "foo/main.nim"
    assert childPathTail("/home/bob/foo", "/home/bob/foobar").isNone
  let root = path # here path is always already normalized projectDir
  let child = normalizePathUniform(subpath)
  if child.startsWith(root) and
    ((child.len - root.len) == 0 or child[root.len] in {DirSep, AltSep}):
    some(child.substr(root.len + 1)) # substr is safe
  else:
    none(string)
#[------- /Utils -------]#

iterator findWaves(src: string): ChunkRec =
  ## Searches all SOURCE WAVE files and returns ChunkRec:
  ## `pre`: indexes from start of text chunk up to "WAVE" marker,
  ## `mid`: from right after WAVE up to file quote,
  ## `name`: text inside the quotes.
  let skt: SkipTable = initSkipTable(SourceMarker)
  var start = 0
  while start < src.len:
    let srcMarker = skt.find(src, SourceMarker, start, src.len)
    var fr: ChunkRec
    if srcMarker >= 0:
      let
        srcEnd = Natural(srcMarker + SourceMarker.len)
        srcLow = Natural(srcEnd - CodecStrs[CWav].mark.len() - 1)
        fileLow = src.find(FileMarker, srcEnd, src.len) + FileMarker.len
        fileHi = src.find('"', fileLow, src.len) - 1
      if fileLow < 0 or fileHi < 0: panic("Aborted: Invalid project file")
      let name = src.substr(fileLow, fileHi)
      fr = ChunkRec(
        pre: Natural(start)..srcLow,
        mid: srcEnd..Natural(fileLow-1),
        name: name)
      start = fileHi + 1 # safe, otherwise already panicked
    else: # tail or the whole file if nothing was found
      fr = ChunkRec(pre: (Natural(start)..Natural(src.high)), name: "")
      start = src.len # break after yield
    yield fr

proc setOutput(fname: string; overwrite: bool): File =
  if fileExists(fname) and not overwrite:
    panic("Output file exists, not overwriting!")
  var f: File
  if f.open(fname, fmWrite):
    f
  else:
    panic("Could not open output file")

proc getUniqueFileName(relDir, name: string; codec: Codec): string =
  var suffix = ""
  for counter in 1..high(int):
    # joinPath negates possible sep changes in normalizePathUniform: replaces with `DirSep`
    result = joinPath(relDir, name & suffix & CodecStrs[codec].ext)
    if fileExists(result): suffix = "-" & $counter
    else: return result
  assert(false, "Counter exhausted. Likely a bug.")

proc convCandidate(fPath: string; codec: Codec): Option[string] =
  ## Returns a unique available name for a converted file
  if fPath.len > 0:
    var (relDir, name, ext) = splitFile(fPath)
    if ext.toLowerAscii() == ".wav":            # Skip all non-wav files
      result = some(getUniqueFileName(relDir, name, codec))

proc doClean(wavPath: string) =
  proc rm(path: string) =
    if tryRemoveFile(path): warn(&"{path} removed")
    else: err(&"{path} error removing")
  let reapeaksPath = wavPath & ".reapeaks"
  if fileExists(wavPath): rm(wavPath)
  if fileExists(reapeaksPath): rm(reapeaksPath)


proc print(file: File; project: openArray[char]; ch: ChunkRec;
           codec: Codec; name: string = "") =
  discard file.writeChars(project[ch.pre], 0, ch.pre.len)
  if ch.mid.a > ch.pre.a:
    file.write(CodecStrs[codec].mark)
    discard file.writeChars(project[ch.mid], 0, ch.mid.len)
    file.write(if name != "": name else: ch.name)

proc codecIsAvailable(codec: Codec): Option[string] =
  ## Check if invoking a binary with the `--version` parameter successfully
  ## prints a string starting with codec's binary name.
  ## True for `flac` and `wavpack`.
  let (output, exitCode) = try:
      execCmdEx(CodecStrs[codec].bin & " --version", {poStdErrToStdOut, poUsePath})
    except CatchableError:
      return none(string)
  if exitCode == 0 and output.startsWith(CodecStrs[codec].bin):
    var firstLine: string = newStringOfCap(14)
    for line in output.splitLines(): # return only the first line
      firstLine = line; break
    some(firstLine)
  else:
    none(string)

proc convertAndCullFailed[T: string](table: var Associative[T, (Codec, T)]) =
  # Tried to minimize juggling string pairs aroud:
  # [M] - main thread; [T] - Task thread; [R] - receiver thread
  # - [M] Iterate table pairs, record pair indexes
  # - [M] Send pair+index to conversion thread
  # - [T] Convert & send back exit codes and output name for logging + idx for cleanup
  # - [R] After conversion log names and mark failed indexes
  # - [M] Remove failed pairs from the table, to skip them when changing the Project file
  let nTasks = table.len()
  var
    pool: CozyTaskPool = newTaskPool()
    keys = newSeqOfCap[string](nTasks)
    failedIdxs {.global.}: seq[Natural]

  proc logger(outP: string; idx: int; exitCode: int) =
    {.gcsafe.}: # All logging must go through this proc invoked by a single thread
      if exitCode == 0:
        log(outP)
      else:
        err(outP)
        failedIdxs.add(idx) # Mark failed

  proc conversion(resCh: ptr Chan[Task]; inP, outP: string; codec: Codec; idx: int) =
    var args: seq[string]
    case codec
      of CFlac: args = @["--best", "-s", "--keep-foreign-metadata", "-o", outP, inP]
      of CWavpack: args = @["-hh", "-t", "-x3", "--no-overwrite", "-q", "-z", inP, outP]
      of CWav: assert(false)
    var exitCode = 0
    try:
      let p = startProcess(CodecStrs[codec].bin, options={poUsePath, poStdErrToStdOut}, args=args)
      exitCode = p.waitForExit()
      p.close()
    except OSError: exitCode = 1
    resCh[].send(toTask(logger(outP, idx, exitCode)))

  for idx, inP, (codec, outP) in enumerate(table.pairs):
    keys.add(inP)
    pool.sendTask(toTask( conversion(pool.resultsAddr(), inP, outP, codec, idx) ))

  pool.stopPool()
  for idx in failedIdxs: table.excl(keys[idx]) # Cull failed

proc chooseCodec(path: string): Codec =
  ## Flac by default, WavPack if 64/32 bit float
  try:
    let wavHeader = readWavFileHeader(path)
    if wavHeader.isFloat and wavHeader.bitsPerSample in {32, 64}: CWavpack
    else: CFlac
  except CatchableError:
    warn(&"Error reading '{path}'. Trying Flac anyway.")
    CFlac

proc main(input: string; output: string = "";
  overwrite = false, cleanup = false, confirm = true, wvonly = false) =
  let
    project = readFile(input)
    outputAbs = absolutePath(output)
    projectDir = input.splitPath()[0].absolutePath().normalizePathUniform()
  var prChunks: seq[ChunkRec]
  var toConvert: CritBitTree[(Codec, string)]
  setCurrentDir(projectDir)

  var wavpackRequested = false
  for ch in project.findWaves():
    prChunks.add(ch) # Add all, including the trailing chunk with an empty name
    if ch.name.len > 0 and ch.name notin toConvert:
      let relPath = if ch.name.isAbsolute(): childPathTail(projectDir, ch.name)
        else: some(ch.name.normalizePath())
      if relPath.isSome:
        let path = relPath.unsafeGet()
        let codec = if not wvonly: chooseCodec(path) else: CWavpack
        if codec == CWavpack: wavpackRequested = true
        let pairOp = convCandidate(path, codec)
        if pairOp.isSome(): toConvert[ch.name] = (codec, pairOp.unsafeGet())

  if toConvert.len == 0:
    info("No WAV files to compress found in the project, exiting.")
    quit(0)

  if confirm:
    for inP, (_, outP) in toConvert.pairs():
      info(inP, "\t", outP)

  # Delayed so it's possible to get a conversion list in any case
  let basecodec = if wvonly: CWavpack else: CFlac
  if not codecIsAvailable(basecodec).isSome():
    panic("Aborted: ", CodecStrs[basecodec].bin, " binary is not available!")
  if not wvonly and wavpackRequested and not codecIsAvailable(CWavpack).isSome():
    err("Wavpack is not available, 64b/32b floating point files won't be compressed!")

  if confirm:
    stderr.writeLine("Continue? [Y/Enter]: ")
    if getch() notin ['y', 'Y', char(13)]: return

  var outF = if output == "": stdout else: setOutput(outputAbs, overwrite)

  convertAndCullFailed(toConvert)

  for ch in prChunks:
    if toConvert.hasKey(ch.name): # Option pattern matching in Nim when?
      let (codec, outP) = toConvert[ch.name]
      outF.print(project, ch, codec, outP)
    else:
      outF.print(project, ch, CWav)

  if cleanUp: (for inP in toConvert.keys(): doClean(inP))

proc healthCheck() =
  for codec in CFlac..Codec.high: # skip CWav
    let output = codecIsAvailable(codec)
    if output.isSome():
      log(output.unsafeGet())
    else:
      warn(CodecStrs[codec].bin, " not available!")

when isMainModule:
  exitprocs.addExitProc((proc() = resetAttributes(stderr))) # TODO: necessary still?
  var p = newParser:
    help(HelpStr)
    flag("-f", "--overwrite", help="Overwrite output RPP")
    flag("-x", "--cleanup", help="Remove converted WAV files and their reapeaks")
    flag("-y", "--noconfirm", help="Skip confirmation, don't print the conversion list")
    flag("-w", "--wv", help="Use wavpack encoding only (if available)")
    flag("-c", "--healthcheck", help="Check available codec binaries and exit", shortcircuit = true)
    flag("-v", "--version", help="Print version and exit", shortcircuit = true)
    option("-o", "--output", help="Output RPP name")
    arg("INPUT_rpp", nargs = 1, help = "Path to input Reaper project")
  try:
    newCozyLogWriter(stderr)
    let opts = p.parse(commandLineParams())
    if opts.INPUT_rpp.len > 0 and fileExists(opts.INPUT_rpp):
      main(opts.INPUT_rpp, opts.output, opts.overwrite, opts.cleanup,
        confirm = (not opts.noconfirm) and stdin.isatty, opts.wv)
    else:
      panic("Input file does not exist or is not accessible!")
  except ShortCircuit as err:
    if err.flag == "argparse_help": echo p.help
    elif err.flag == "version": echo fmt"rearchiver {NimblePkgVersion}"
    elif err.flag == "healthcheck":
      newCozyLogWriter(stdout)
      healthCheck()
  except UsageError:
    panic(getCurrentExceptionMsg())
