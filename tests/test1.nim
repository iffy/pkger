import std/os
import std/strformat
import std/random
import std/unittest

import pkger

randomize()
proc tmpDir*(): string =
  result = os.getTempDir() / &"test{random.rand(10000000)}"
  result.createDir()

template withinTmpDir*(body:untyped):untyped =
  let
    tmp = tmpDir()
    olddir = getCurrentDir()
  setCurrentDir(tmp)
  body
  setCurrentDir(olddir)
  try:
    tmp.removeDir()
  except:
    echo "WARNING: failed to remove temporary test directory: ", getCurrentExceptionMsg()


test "updatepackagelist":
  withinTmpDir:
    cli @["init"]
    cli @["low", "updatepackagelist"]
    check dirExists("pkger"/"packages")
    check fileExists("pkger"/"packages.sqlite")
