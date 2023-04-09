import std/[tasks, osproc], threading/channels

when not defined(gcArc) and not defined(gcOrc) and not defined(nimdoc):
  {.error: "This package requires --mm:arc or --mm:orc".}

type
  RunnerArgs = tuple[tasks: ptr Chan[Task], results: ptr Chan[Task]]
  ConsumerArgs = tuple[results: ptr Chan[Task], nthreads: Positive]
  CozyTaskPool* = object
    nthreads: Positive
    taskThreads: seq[Thread[RunnerArgs]]
    consumerThread: Thread[ConsumerArgs]
    tasks: Chan[Task]
    results: Chan[Task]
  StopFlag = object of CatchableError

proc stop() = raise newException(StopFlag, "")

proc runner(args: RunnerArgs) {.thread.} =
  var t: Task
  while true:
    args.tasks[].recv(t)
    try: t.invoke()
    except StopFlag: break
  args.results[].send(toTask(stop())) # notify consumer thread finished

proc consumer(args: ConsumerArgs) {.thread.} =
  var activethreads: Natural = args.nthreads
  var t: Task
  while activethreads > 0:
    args.results[].recv(t)
    try: t.invoke()
    except StopFlag: dec(activethreads)

func resultsAddr*(pool: CozyTaskPool): ptr Chan[Task] {.inline.} =
  pool.results.addr

proc sendTask*(pool: var CozyTaskPool; task: sink Task) {.inline.} =
  pool.tasks.send(isolate(task))

proc newTaskPool*(nthreads: Positive = countProcessors()): CozyTaskPool =
  result.nthreads = nthreads
  result.taskThreads = newSeq[Thread[RunnerArgs]](nthreads)
  result.tasks = newChan[Task]()
  result.results = newChan[Task]()
  createThread(result.consumerThread, consumer, (result.results.addr, nthreads))
  for ti in 0..high(result.taskThreads):
    createThread(result.taskThreads[ti], runner, (result.tasks.addr, result.results.addr))
  result

proc stopPool*(pool: var CozyTaskPool) =
  for _ in pool.taskThreads: pool.tasks.send(toTask(stop()))
  joinThreads(pool.taskThreads)
  joinThread(pool.consumerThread)


when isMainModule:
  import std/[tasks, os, unittest], threading/channels

  var
    data = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61]
    checkset: set[byte] = {1, 2, 4, 6, 10, 12, 16, 18, 22, 28, 30, 36, 40, 42, 46, 52, 58, 60}
    results: set[byte]

  suite "Cozy Task Pool test suite":
    setup:
      var pool: CozyTaskPool = newTaskPool()

    test "Test completion":
      proc log(inputData: int) =
        results.incl(inputData.byte)
        # echo "Received some message about ", inputData

      proc work(consumer: ptr Chan[Task]; inputData: int) =
        sleep(100)
        let r = inputData - 1
        consumer[].send(toTask( log(r) ))

      for x in data:
        pool.sendTask(toTask( work(pool.resultsAddr(), x) ))

      pool.stopPool()
      check results == checkset
