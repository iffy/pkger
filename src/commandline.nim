import std/algorithm
import std/logging
import std/os
import std/osproc
import std/sequtils
import std/strformat
import std/strutils
import std/tables

putEnv("GIT_TERMINAL_PROMPT", "0")

proc niceDir*(x: string): string =
  ## Return a friendly relative or absolute path 
  var paths = @[
    "~" / relativePath(x, getHomeDir()),
    relativePath(x, getCurrentDir()),
    absolutePath(x),
  ]
  paths.sort(proc (a,b: string): int =
    cmp(a.len, b.len)
  )
  paths[0]

proc runsh*(args: seq[string], workingDir = "") =
  let
    cmd = args[0]
    otherargs = args[1..^1]
  var logline = if workingDir == "": "$ " else: workingDir.niceDir & " $ "
  logline.add(args.mapIt(quoteShell(it)).join(" "))
  info &"[EXEC] {logline}"
  try:
    var p = startProcess(cmd,
      workingDir = workingDir,
      args = otherargs,
      options = {poUsePath, poParentStreams})
    let pid = p.processID()
    let rc = p.waitForExit()
    p.close()
  except:
    error &"[EXEC] error running {logline}"
    error getCurrentExceptionMsg()
    raise
  if rc != 0:
    error &"[{pid}] FAILED {rc}"
    raise ValueError.newException("Error running: " & $args)

proc runshout*(args: seq[string], workingDir = "", silent = false): string =
  let
    cmd = args[0]
    otherargs = args[1..^1]
  var logline = if workingDir == "": "$ " else: workingDir.niceDir & " $ "
  logline.add(args.mapIt(quoteShell(it)).join(" "))
  if not silent:
    info &"[EXEC] {logline}"
  try:
    execProcess(cmd,
      workingDir = workingDir,
      args = otherargs,
      options = {poUsePath})
  except:
    error &"[EXEC] error running {logline}"
    error getCurrentExceptionMsg()
    raise
