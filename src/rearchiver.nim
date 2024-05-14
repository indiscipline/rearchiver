import std/[strutils, strformat, terminal, osproc, options, tables, tasks, enumerate, exitprocs]
import fusion/btreetables
import pkg/[argparse]
import threading/channels
import ../cozytaskpool/src/cozytaskpool
import ../cozylogwriter/cozylogwriter
from std/os import splitFile, joinPath, getCurrentDir

#{.experimental: "views".}

const
  ## Autodefined by Nimble. If built using pure nim, use git tag
  NimblePkgVersion {.strdefine.} = staticExec("git describe --tags HEAD").strip()
  HelpStr = """Convert WAV files used in a Reaper project to FLAC for archiing.
  A working FLAC binary by xiph.org accessible by your environment is required.
  Outputs the edited RPP file to stdout, or writes to a file path given (`-o`).
  Prints a tab-separated list of file pairs to convert unless `-y` is used.
  Logs to STDERR.

  No guarantees."""
  SourceMarker = "<SOURCE WAVE"
  FileMarker = "FILE \""
  NewExt = ".flac"

type
  SrcType = enum
    WAVE, FLAC
  ChunkRec = object
    pre: Slice[Natural] # Chunk up to "<SOURCE "
    mid: Slice[Natural] # Chunk from after "WAVE" up to end of "FILE \""
    name: string # Value of FILE
  Associative[T, U] = concept t, var u
    t[T] is U
    u.del(T)
    t.pairs is (T, U)

func isAbsolute(path: string): bool =
  ## Force windows paths to be considered absolute on linux
  (path.len > 1 and path[0] in {'a'..'z', 'A'..'Z'} and path[1] == ':') or
  os.isAbsolute(path)

iterator findWaves(src: string): ChunkRec =
  ## Searches all SOURCE WAVE files and returns ChunkRec:
  ## `pre`: indexes from start of text chunk up to "WAVE",
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
        srcLow = Natural(srcEnd - 4 - 1)
        fileLow = src.find(FileMarker, srcEnd, src.len) + FileMarker.len
        fileHi = src.find('"', fileLow, src.len) - 1
      if fileLow < 0 or fileHi < 0: panic("Aborted: Invalid project file")
      let name = src.substr(fileLow, fileHi).replace('\\', '/')
      fr = ChunkRec(
        pre: Natural(start)..srcLow,
        mid: srcEnd..Natural(fileLow-1),
        name: name)
      start = fileHi + 1
    else:
      fr = ChunkRec(pre: (Natural(start)..Natural(src.high)), name: "")
      start = src.len
    yield fr

proc setOutput(fname: string; overwrite: bool): File =
  if fileExists(fname) and not overwrite:
    panic("Output file exists, not overwriting!")
  var f: File
  if f.open(fname, fmWrite):
    f
  else:
    panic("Could not open output file")

proc getUniquelyNamedFile(relDir, name: string): string =
  result = joinPath(relDir, name & NewExt)
  var suffix = 1
  while fileExists(result):
    result = joinPath(relDir, &"{name}-{suffix}{NewExt}")
    suffix.inc()

proc convCandidate(fPath: string): Option[string] =
  ## Checks if file is in a project dir (any absolute path considered out)
  ## and returns a unique available name for a converted file
  if not fPath.isAbsolute():
    var (relDir, name, ext) = splitFile(fPath)
    if ext.toLowerAscii() == ".wav":            # Skip all non-wav files
      result = some(getUniquelyNamedFile(relDir, name))

proc doClean(wavPath: string) =
  proc rm(path: string) =
    if tryRemoveFile(path): warn(&"• {path} removed")
    else: err(&"○ {path} error removing")
  let reapeaksPath = wavPath & ".reapeaks"
  if fileExists(wavPath): rm(wavPath)
  if fileExists(reapeaksPath): rm(reapeaksPath)


proc print(file: File; project: openArray[char]; ch: ChunkRec;
           sT: SrcType = WAVE; name: string = "") =
  discard file.writeChars(project[ch.pre], 0, ch.pre.len)
  if ch.mid.a > ch.pre.a:
    file.write($sT)
    discard file.writeChars(project[ch.mid], 0, ch.mid.len)
    file.write(if name != "": name else: ch.name)

proc flacIsAvailable(): bool =
  const Cmd = "flac --version"
  let (output, exitCode) = execCmdEx(Cmd, {poStdErrToStdOut, poUsePath})
  exitCode == 0 and output.len > 4 and
  # check if output starts with `flac`
  (for i in 0..3: (if output[i] != Cmd[i]: return false); true)

proc convertAndCullFailed[T: string](table: var Associative[T, T]) =
  # Tried to minimize juggling string pairs aroud:
  # [M] - main thread; [T] - Task thread; [R] - receiver thread
  # - [M] Iterate table pairs, record pair indexes
  # - [M] Send pair+index to conversion thread
  # - [T] Convert & send back exit codes and output name for logging + idx for cleanup
  # - [R] On conversion results log names and mark failed indexes
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

  proc conversion(resCh: ptr Chan[Task]; inP, outP: string; idx: int) =
    let p = startProcess("flac", options={poUsePath, poStdErrToStdOut},
      args=["-8", "-s", "--keep-foreign-metadata", "-o", outP, inP] )
    let exitCode = p.waitForExit()
    p.close()
    resCh[].send(toTask(logger(outP, idx, exitCode)))

  for idx, (inP, outP) in enumerate(table.pairs):
    keys.add(inP)
    pool.sendTask(toTask( conversion(pool.resultsAddr(), inP, outP, idx) ))

  pool.stopPool()
  for idx in failedIdxs: table.del(keys[idx]) # Cull failed

proc main(input: string; output: string = ""; overwrite: bool = false;
  cleanup: bool = false; confirm: bool = true) =
  let project = readFile(input)
  let outputAbs = absolutePath(output)
  var prChunks: seq[ChunkRec]
  var toConvert: btreetables.Table[string, string]
  setCurrentDir(input.splitPath()[0].absolutePath())

  for ch in project.findWaves():
    prChunks.add(ch)
    let pOp = convCandidate(ch.name)
    if pOp.isSome(): toConvert[ch.name] = pOp.get()

  if confirm:
    for inP, outP in toConvert.pairs():
      info(inP, "\t", outP)

  # Delayed so it's possible to get a conversion list in any case
  if not flacIsAvailable(): panic("Aborted: flac binary is not available!")

  if confirm:
    stderr.writeLine("Continue? [Y/Enter]: ")
    if getch() notin ['y', 'Y', char(13)]: return

  var outF = if output == "": stdout else: setOutput(outputAbs, overwrite)

  convertAndCullFailed(toConvert)

  for ch in prChunks:
    if toConvert.hasKey(ch.name): # BTreeTables don't have single-lookup-get :(
      let outP = toConvert[ch.name]
      outF.print(project, ch, FLAC, outP)
    else:
      outF.print(project, ch, WAVE)

  if cleanUp: (for inP in toConvert.keys(): doClean(inP))


when isMainModule:
  exitprocs.addExitProc((proc() = resetAttributes(stderr)))
  var p = newParser:
    help(HelpStr)
    flag("-f", "--overwrite", help="Overwrite output RPP file if exists")
    flag("-x", "--cleanup", help="Remove converted source WAV files")
    flag("-y", "--noconfirm", help="Don't print conversion list and wait for confirmation")
    flag("-v", "--version", help="Print version and exit", shortcircuit = true)
    option("-o", "--output", help="Output RPP name")
    arg("INPUT_rpp", nargs = 1, help = "Path to input Reaper project")
  newCozyLogWriter(stderr)
  try:
    let opts = p.parse(commandLineParams())
    if fileExists(opts.INPUT_rpp):
      main(opts.INPUT_rpp, opts.output, opts.overwrite, opts.cleanup,
        confirm = (not opts.noconfirm) and stdin.isatty)
    else:
      panic("Input file does not exist or is not accessible!")
  except ShortCircuit as err:
    if err.flag == "argparse_help": echo p.help
    if err.flag == "version": echo fmt"rearchiver {NimblePkgVersion}"
  except UsageError:
    panic(getCurrentExceptionMsg())
