import std/logging
import std/os
import std/osproc
import std/sequtils
import std/strformat
import std/strutils
import std/tables

putEnv("GIT_TERMINAL_PROMPT", "0")

proc runsh*(args: seq[string], workingDir = "") =
  let
    cmd = args[0]
    otherargs = args[1..^1]
  var logline = if workingDir == "": "$ " else: relativePath(workingDir, getCurrentDir()) & " $ "
  logline.add(args.mapIt(quoteShell(it)).join(" "))
  info &"[EXEC] {logline}"
  var p = startProcess(cmd,
    workingDir = workingDir,
    args = otherargs,
    options = {poUsePath, poParentStreams})
  let pid = p.processID()
  let rc = p.waitForExit()
  p.close()
  if rc != 0:
    error &"[{pid}] FAILED {rc}"
    raise ValueError.newException("Error running: " & $args)

proc runshout*(args: seq[string], workingDir = ""): string =
  let
    cmd = args[0]
    otherargs = args[1..^1]
  var logline = if workingDir == "": "$ " else: relativePath(workingDir, getCurrentDir()) & " $ "
  logline.add(args.mapIt(quoteShell(it)).join(" "))
  info &"[EXEC] {logline}"
  execProcess(cmd,
    workingDir = workingDir,
    args = otherargs,
    options = {poUsePath})
