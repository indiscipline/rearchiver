# Cozy Task Pool

Just a repeating pattern of launching `tasks` concurrently in threads with `threading/channels`, extracted into its own micro package.
Not very ergonomic, just hides some of the boilerplate of preparing and tearing down everything.

**Requires** `--threads:on` and (`--mm:arc` or `--mm:orc`)

## Installation
Currently not in nimble directory.

```
nimble install https://github.com/indiscipline/cozytaskpool
```

## Usage
Look at the executable part of the source, which is almost the copy of the following block:

```nim
import std/[tasks], threading/channels

var
  data = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61]
  pool: CozyTaskPool = newTaskPool()

proc log(inputData: int) =
  echo "Received some message about ", inputData

proc work(consumer: ptr Chan[Task]; inputData: int) =
  doTheWork(inputData)
  consumer[].send(toTask( log(inputData) ))

for x in data:
  pool.sendTask(toTask( work(pool.resultsAddr(), x) ))

pool.stopPool()
```

## License
Cozy Task Pool is licensed under GNU General Public License version 2.0 or later;
