# Rearchiver <img src="rearchiver.svg" align="right" alt="Rearchiver logo" width="20%"/>
[![License](https://img.shields.io/badge/license-GPLv3-blue.svg)](https://github.com/indiscipline/rearchiver/blob/master/LICENSE.md)
> [Third Hemisphere Studio](https://thirdhemisphere.studio) tooling

Rearchiver prepares your [Reaper](https://reaper.fm) project for archiving:

- Scans the project file for all used WAV files
- Finds them in the project directory and converts to FLAC / WavPack
- Changes the links to the successfully converted source files in the project accordingly
- Optionally deletes processed source files and their `.reapeaks`
- Outputs the corrected project file

The `flac` encoder is used by default.
`wavpack` is used for 64 or 32 bit floating point PCM files (which FLAC does not support) or for all files, if launched with the `--wv` option.

## Usage
Rearchiver relies on **[Flac](https://xiph.org/flac/download.html)** and **[WavPack](https://www.wavpack.com/downloads.html)** for conversions,
so at least one of the `flac` and `wavpack` programs must be present in your PATH or placed in the same directory as the `rearchiver` executable.

By default[^1] the edited project file is written to a new file with the same base name as the input project plus the *"_archived.rpp"* suffix.
You can write to standard output by setting the `--output` option to "-".

- Save to a default file (writes to *"INPUT_archived.rpp"*):\
  ```rearchiver INPUT.rpp```
- Save to a file:\
  ```rearchiver -o output.rpp INPUT.rpp```
- Write to standard output:\
  ```rearchiver -o - INPUT.rpp```

Converted media files are placed beside the originals (in the same directory).

Rearchiver is interactive and will print the pairs of the found WAV files and the proposed names for the compressed files for user overview.
A confirmation is required then. Use `-y` to skip interactive confirmation.

Full list of options is available: `rearchiver --help`.

## Disclaimer
Rearchiver tries to be conservative and will not overwrite anything unless asked by the user. However, there might be bugs.\
This software is provided without any guarantees.

## Installation
Rearchiver is tested to work under Windows and GNU/Linux. Probably works on OSX with no changes.

Download a binary from the [release assets](https://github.com/indiscipline/rearchiver/releases/latest) or compile yourself.

### Building manually
Building requires the Nim compiler and a Nim package manager (such as Nimble) to resolve the dependencies.
Third-party libraries Rearchiver relies on: [`threading`](https://github.com/nim-lang/threading), [`argparse`](https://github.com/iffy/nim-argparse).
Use `choosenim` to install and manage the Nim compilation toolchain.

To install with Nimble:

```
nimble install https://github.com/indiscipline/rearchiver
rearchiver -h
```

## TODO:
- [x] Add support for WavPack as an alternative codec / codec supporting 32 bit float WAV files
- [ ] Migrate to a proper pool for managing concurrent process execution
- [ ] Consider if there are any practical benefits in properly parsing the project file, instead of doing it by dumb text substitution

## Contributing
The project is open for contributions. Please, try to limit the scope of your changes.

Open an issue for bugs, ideas and feature requests.

## License
Rearchiver is licensed under GNU General Public License version 3.0 or later; See `LICENSE.md` for full details.

[Logo](rearchiver.svg) is licensed under Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)

[^1]: Since v0.2.0. Previously wrote to stdout by default.