# Rearchiver <img src="rearchiver.svg" align="right" alt="Rearchiver logo" width="20%"/>
> [Third Hemisphere Studio](https://thirdhemisphere.studio) tooling

Rearchiver prepares your [Reaper](https://reaper.fm) project for archiving:

- Scans the project file for all used WAV files
- Finds them in the project directory and converts to FLAC
- Changes the links to the successfully converted source files input RPP file accordingly
- Optionally deletes processed source files and their `.reapeaks`
- Outputs the corrected project file

Only WAV files supported by the `flac` binary can be converted. Currently, this means 32 bit floating point PCM files will be skipped and left uncompressed!

## Usage
Rearchiver relies on **[Flac](https://xiph.org/flac/download.html)** for conversions,
so the `flac` program must be present in your PATH or placed in the same directory as `rearchiver` executable.

By default the edited project file is written to the standard output, use redirection or `-o` to write to a file:

```
# redirect standard output to a file
> rearchiver INPUT.rpp > output.rpp
# write to a file
> rearchiver INPUT.rpp -o output2.rpp
```

Rearchiver is interactive, it will print the pairs of the found WAV files and the proposed names for the FLACs and will ask for your confirmation. Use `-y` to bypass the confirmation.

Additional options are available in help: `rearchiver --help`.

## Disclaimer
Rearchiver tries to be conservative and will not overwrite anything unless asked by the user. However, there might be bugs.\
This software is provided without any guarantees.

## Installation
Rearchiver is tested to work under Windows and GNU/Linux. Probably works on OSX with no changes.

Download a binary from the [release assets](https://github.com/indiscipline/rearchiver/releases/latest) or compile yourself.

### Building manually
Building requires the Nim compiler and a Nim package manager (such as Nimble) to resolve the dependencies.
Third-party libraries Rearchiver relies on: `fusion`, `threading`, `argparse`.
Use `choosenim` to install and manage the Nim compilation toolchain.

To install with Nimble:

```
nimble install https://github.com/indiscipline/rearchiver
rearchiver -h
```

## TODO:
- [ ] Add support for WavPack as an alternative codec / codec supporting 32 bit float WAV files
- [ ] Migrate to a proper pool for managing concurrent process execution
- [ ] Consider if there are any practical benefits in properly parsing the project file, instead of doing it by dumb text substitution

## Contributing
The project is open for contributions. Please, try to limit the scope of your changes.

Open an issue for bugs, ideas and feature requests.

## License
Rearchiver is licensed under GNU General Public License version 3.0 or later; See `LICENSE.md` for full details.

[Logo](rearchiver.svg) is licensed under Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)
