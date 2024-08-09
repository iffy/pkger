import std/logging
import std/options
import std/os
import std/osproc
import std/random
import std/strformat
import std/strutils
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

addHandler(newConsoleLogger())

let localPackagesRepo = currentSourcePath().parentDir/"data"/"packagesrepo"
if not dirExists(localPackagesRepo):
  echo "Cloning nim-lang/packages cache for testing"
  discard execProcess("git",
    args=["clone", "https://github.com/nim-lang/packages", localPackagesRepo],
    options={poUsePath, poStdErrToStdOut})

test "init":
  withinTmpDir:
    cli @["init"]
    check fileExists("pkger.json")
    check dirExists("pkger")
    check fileExists("pkger"/".gitignore")

test "updatepackagelist":
  withinTmpDir:
    cli @["init"]
    check dirExists("pkger"/"packages")
    var ctx = pkgerContext()
    check ctx.getPackage("argparse").get.url == "https://github.com/iffy/nim-argparse"

test "updatepackagelist again":
  withinTmpDir:
    cli @["init"]
    cli @["low", "updatepackagelist"]

suite "use":
  test "use localpath":
    withinTmpDir:
      cli @["init"]
      createDir("foobar")
      writeFile("foobar"/"foobar.nimble", "# garbage nimble file")
      cli @["use", "./foobar"]
      check "--path:\"foobar\"" in readFile("nim.cfg")
      check "foobar" in readFile("pkger"/"deps.json")

      echo readFile("pkger"/"deps.json")
      echo readFile("nim.cfg")

  test "use name":
    withinTmpDir:
      cli @["init"]
      cli @["use", "argparse"]
      check dirExists("pkger"/"lazy"/"argparse")
      check "argparse" in readFile("pkger"/"deps.json")
      check "--path:\"pkger/lazy/argparse/src\"" in readFile("nim.cfg")
      checkpoint readFile("pkger"/"deps.json")
      
      removeDir("pkger"/"lazy")
      cli @["fetch"]
      check dirExists("pkger"/"lazy"/"argparse")

  test "use name@hash":
    withinTmpDir:
      cli @["init"]
      cli @["use", "argparse@ce7b23e72dcfd1a962ce12e5943ef002a0f46e37"]
      check dirExists("pkger"/"lazy"/"argparse")
      checkpoint readFile("pkger"/"deps.json")

      let deps = readFile("pkger"/"deps.json")
      check "argparse" in deps
      check "ce7b23e72dcfd1a962ce12e5943ef002a0f46e37" in deps
      check "2.0.0" in readFile("pkger"/"lazy"/"argparse"/"argparse.nimble")

  test "use name@version":
    withinTmpDir:
      cli @["init"]
      cli @["use", "argparse@2.0.0"]
      check dirExists("pkger"/"lazy"/"argparse")
      checkpoint readFile("pkger"/"deps.json")

      let deps = readFile("pkger"/"deps.json")
      check "argparse" in deps
      check "ce7b23e72dcfd1a962ce12e5943ef002a0f46e37" in deps
      check "2.0.0" in readFile("pkger"/"lazy"/"argparse"/"argparse.nimble")

  test "use url":
    withinTmpDir:
      cli @["init"]
      cli @["use", "https://github.com/iffy/nim-argparse.git"]
      check dirExists("pkger"/"lazy"/"argparse")
      check "argparse" in readFile("pkger"/"deps.json")
      check "--path:\"pkger/lazy/argparse/src\"" in readFile("nim.cfg")
      checkpoint readFile("pkger"/"deps.json")
      
      removeDir("pkger"/"lazy")
      cli @["fetch"]
      check dirExists("pkger"/"lazy"/"argparse")

  test "use url@hash":
    withinTmpDir:
      cli @["init"]
      cli @["use", "https://github.com/iffy/nim-argparse.git@ce7b23e72dcfd1a962ce12e5943ef002a0f46e37"]
      check dirExists("pkger"/"lazy"/"argparse")
      checkpoint readFile("pkger"/"deps.json")

      let deps = readFile("pkger"/"deps.json")
      check "argparse" in deps
      check "ce7b23e72dcfd1a962ce12e5943ef002a0f46e37" in deps
      check "2.0.0" in readFile("pkger"/"lazy"/"argparse"/"argparse.nimble")

  test "use url@version":
    withinTmpDir:
      cli @["init"]
      cli @["use", "https://github.com/iffy/nim-argparse.git@2.0.0"]
      check dirExists("pkger"/"lazy"/"argparse")
      checkpoint readFile("pkger"/"deps.json")

      let deps = readFile("pkger"/"deps.json")
      check "argparse" in deps
      check "ce7b23e72dcfd1a962ce12e5943ef002a0f46e37" in deps
      check "2.0.0" in readFile("pkger"/"lazy"/"argparse"/"argparse.nimble")

  test "use url@tag":
    withinTmpDir:
      cli @["init"]
      cli @["use", "https://github.com/iffy/nim-argparse.git@v2.0.0"]
      check dirExists("pkger"/"lazy"/"argparse")
      checkpoint readFile("pkger"/"deps.json")

      let deps = readFile("pkger"/"deps.json")
      check "argparse" in deps
      check "ce7b23e72dcfd1a962ce12e5943ef002a0f46e37" in deps
      check "2.0.0" in readFile("pkger"/"lazy"/"argparse"/"argparse.nimble")

  test "use url@branch":
    withinTmpDir:
      cli @["init"]
      cli @["use", "https://github.com/iffy/nim-argparse.git@master"]
      check dirExists("pkger"/"lazy"/"argparse")
      checkpoint readFile("pkger"/"deps.json")

      let deps = readFile("pkger"/"deps.json")
      check "argparse" in deps
