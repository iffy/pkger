import std/logging
import std/options
import std/os
import std/osproc
import std/random
import std/streams
import std/strformat
import std/strutils
import std/unittest

import pkger

randomize()
const TEMPDIR_ROOT = currentSourcePath().parentDir()/"_tmp"
if dirExists(TEMPDIR_ROOT):
  removeDir(TEMPDIR_ROOT)
createDir(TEMPDIR_ROOT)
proc tmpDir*(): string =
  result = TEMPDIR_ROOT / &"test{random.rand(10000000)}"
  result.createDir()

template cd*(dir: string, body: untyped): untyped =
  block:
    let
      olddir = getCurrentDir()
    setCurrentDir(dir)
    body
    setCurrentDir(olddir)

template withinTmpDir*(body:untyped):untyped =
  cd(tmpDir()):
    body

let pkgerbin = currentSourcePath().parentDir().parentDir()/"pkger"
# if not fileExists(pkgerbin):
let pkgersrc = currentSourcePath().parentDir().parentDir()/"src"/"pkger.nim"
discard execCmd("nim c -o:" & quoteShell(pkgerbin) & " " & quoteShell(pkgersrc))

proc cliout*(args: seq[string]): string =
  ## Execute `pkger args...` and capture stdout
  var p = startProcess(pkgerBin, args = args, options = {poUsePath})
  var outp = outputStream(p)
  var errp = errorStream(p)
  result = ""
  var line = newStringOfCap(120)
  var outopen = true
  var erropen = true
  while outopen or erropen:
    if outopen:
      try:
        let line = outp.readLine()
        result.add(line & "\n")
      except:
        outopen = false
    if erropen:
      try:
        let line = errp.readLine()
        stderr.writeLine(line)
      except:
        erropen = false
  close(p)

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
    check dirExists("pkger")
    check fileExists("pkger"/"deps.json")
    check fileExists("pkger"/".gitignore")

suite "updatepackagelist":
  test "basic":
    withinTmpDir:
      cli @["init"]
      var ctx = pkgerContext()
      check dirExists(ctx.packages_repo_dir())
      check ctx.lookupPackageFromRegistry("argparse").get.url == "https://github.com/iffy/nim-argparse"

  test "again":
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
  
  test "use url@tag no v":
    withinTmpDir:
      cli @["init"]
      cli @["use", "hmac@0.3.2"]
      check dirExists("pkger"/"lazy"/"hmac")

  test "use url@branch":
    withinTmpDir:
      cli @["init"]
      cli @["use", "https://github.com/iffy/nim-argparse.git@master"]
      check dirExists("pkger"/"lazy"/"argparse")
      checkpoint readFile("pkger"/"deps.json")

      let deps = readFile("pkger"/"deps.json")
      check "argparse" in deps
  
  test "use url@notmasterbranch":
    withinTmpDir:
      cli @["init"]
      cli @["use", "https://github.com/iffy/nim-checksums@support-1.6.x"]
      let deps = readFile("pkger"/"deps.json")
      check "checksums" in deps
  
  test "use toml nimble":
    withinTmpDir:
      cli @["init"]
      cli @["use", "uuids"]
      cli @["use", "isaac"]
      echo cliout @["status"]
      writeFile("samp.nim", """
import uuids
echo $genUUID()
      """)
      echo execCmd("nim c samp.nim")
  
  # test "use recursive":
  #   withinTmpDir:
  #     cli @["init"]
  #     cli @["use", "changer"]
  #     cli @["status"]
  #     check dirExists("pkger"/"lazy"/"changer")
  #     check dirExists("pkger"/"lazy"/"argparse")
  #     check dirExists("pkger"/"lazy"/"regex")
  #     check dirExists("pkger"/"lazy"/"parsetoml")

suite "remove":
  test "localpath":
    withinTmpDir:
      cli @["init"]
      createDir("foobar")
      writeFile("foobar"/"foobar.nimble", "# garbage nimble file")
      cli @["use", "./foobar"]
      check "--path:\"foobar\"" in readFile("nim.cfg")
      check "foobar" in readFile("pkger"/"deps.json")

      cli @["remove", "foobar"]
      check "--path:\"foobar\"" notin readFile("nim.cfg")
      check "foobar" notin readFile("pkger"/"deps.json")

      echo readFile("pkger"/"deps.json")
      echo readFile("nim.cfg")

  test "by name":
    withinTmpDir:
      cli @["init"]
      cli @["use", "argparse"]
      check dirExists("pkger"/"lazy"/"argparse")
      check "argparse" in readFile("pkger"/"deps.json")
      check "--path:\"pkger/lazy/argparse/src\"" in readFile("nim.cfg")

      cli @["remove", "argparse"]
      checkpoint readFile("pkger"/"deps.json")
      check "argparse" notin readFile("pkger"/"deps.json")
      check "--path:\"pkger/lazy/argparse/src\"" notin readFile("nim.cfg")
      
      removeDir("pkger"/"lazy")
      cli @["fetch"]
      check not dirExists("pkger"/"lazy"/"argparse")  

test "listdeps":
  withinTmpDir:
    writeFile("goo.nimble", """
requires "argparse == 2.0.0"
requires "changer"
requires "madeup >= 5"
    """)
    let deps = cliout @["listdeps", "."]
    echo deps
    check "argparse == 2.0.0" in deps
    check "changer" in deps
    check "madeup >= 5" in deps

test "listdeps singleline":
  withinTmpDir:
    writeFile("goo.nimble", """
requires "nim >= 1.6.10", "nimSHA2", "nimcrypto >= 0.5.4", "checksums >= 0.1.0"
""")
    let deps = cliout @["listdeps", "."]
    echo deps
    check "nimSHA2" in deps
    check "nimcrypto >= 0.5.4" in deps
    check "checksums >= 0.1.0" in deps

test "specific dir":
  withinTmpDir:
    createDir("a")
    cd("a"):
      cli @["init", "--dir", ".."/"packages"]
      cli @["use", "hmac@0.3.2"]
    check dirExists("packages"/"lazy"/"hmac")

suite "status":

  test "package not installed":
    withinTmpDir:
      cli @["init"]
      writeFile("something.nimble", """
        requires "argparse"
        """)
      var status = cliout @["status"]
      echo status
      check "[ ] argparse" in status
      cli @["use", "argparse@2.0.0"]
      status = cliout @["status"]
      echo status
      check "[x] argparse" in status
  
  test "nimble url":
    withinTmpDir:
      cli @["init"]
      writeFile("something.nimble", """
        requires "https://github.com/iffy/nim-argparse.git#master"
        """)
      var status = cliout @["status"]
      echo status
      check "[ ] https://github.com/iffy/nim-argparse.git" in status
      cli @["use", "https://github.com/iffy/nim-argparse.git@master"]
      status = cliout @["status"]
      echo status
      check "[x] https://github.com/iffy/nim-argparse.git" in status

suite "ReqNimbleDesc":

  test "basic":
    let t = ReqNimbleDesc("argparse").parse()
    check t.isUrl == false
    check t.name == "argparse"
    check t.version == ""
  
  test "single version":
    let t = ReqNimbleDesc("argparse == 2.0.0").parse()
    check t.isUrl == false
    check t.name == "argparse"
    check t.version == "== 2.0.0"
  
  test "url":
    let t = ReqNimbleDesc("https://github.com/iffy/nim-argparse.git#ce7b23e72dcfd1a962ce12e5943ef002a0f46e37").parse()
    check t.isUrl == true
    check t.url == "https://github.com/iffy/nim-argparse.git"
    check t.version == "ce7b23e72dcfd1a962ce12e5943ef002a0f46e37"

suite "functional":
  test "websock repo":
    withinTmpDir:
      cli @["init"]
      cli @["use", "https://github.com/status-im/nim-websock"]
      cli @["fetch"]
      removeDir "pkger"/"lazy"/"websock"
      cli @["fetch"]
