import std/logging
import std/strformat
import std/strutils

import argparse

import ./objs
import ./context; export context
import ./deps
import ./packages; export packages

#---------------------------------------------------------
# 
#---------------------------------------------------------
const START_SENTINEL = "### PKGER START - DO NOT EDIT BELOW #########"
const END_SENTINEL =   "### PKGER END - DO NOT EDIT ABOVE ###########"

proc setNimCfgDirs(ctx: PkgerContext, dirs: seq[string]) =
  ## Set a nim.cfg file's paths to the given set
  let existing = try:
      readFile(ctx.rootDir/"nim.cfg")
    except:
      ""
  var body: seq[string]
  body.add("--noNimblePath")
  for dir in dirs:
    body.add("--path:\"" & dir & "\"")
  
  var state = "init"
  var lines: seq[string]
  for line in existing.splitLines():
    case state
    of "init":
      lines.add(line)
      if line == START_SENTINEL:
        lines.add(body)
        state = "inside"
    of "inside":
      if line == END_SENTINEL:
        lines.add(line)
        state = "after"
    of "after":
      lines.add(line)
    else:
      raise ValueError.newException("Invalid state: " & state)
    
  if state == "init":
    lines.add(START_SENTINEL)
    lines.add(body)
    lines.add(END_SENTINEL)
  writeFile(ctx.rootDir/"nim.cfg", lines.join("\n"))

proc use(ctx: PkgerContext, package_desc: string, deps = true) =
  let dep = ctx.placePackage(package_desc, ctx.packageDownloadDir())
  ctx.addNewDeps(@[dep])
  let deps = ctx.getDeps()
  var nimPaths: seq[string]
  for dep in deps:
    let srcPath = ctx.ondiskPath(dep)
    nimPaths.add(getNimPathsFromProject(srcPath).mapIt(relativePath(srcPath/it, ctx.rootDir)))
  ctx.setNimCfgDirs(nimPaths)

proc cmd_fetch(ctx: PkgerContext) =
  ## Fetch all the source packages that are missing
  let deps = ctx.getDeps()
  var newdeps: seq[Dep]
  for dep in deps:
    newdeps.add(ctx.fetch(dep))
  ctx.setDeps(newdeps)

#---------------------------------------------------------
# plumbing
#---------------------------------------------------------
proc cmd_updatepackagelist(ctx: PkgerContext) =
  info &"updating package list for {ctx.rootDir}"
  updatePackagesDir(ctx)

#---------------------------------------------------------
# porcelain
#---------------------------------------------------------
proc cmd_init(dirname: string) =
  info &"initializing pkger in {dirname}"
  if fileExists(dirname/"pkger.json"):
    warn &"pkger already initialized"
    return
  writeFile("pkger.json", "{}")

  let pkgerdir = dirname/"pkger"
  createDir pkgerdir
  writeFile(pkgerdir/".gitignore", "./lazy/*")

  cmd_updatepackagelist(pkgerContext())

proc cmd_use(ctx: PkgerContext, package_desc: string) =
  ctx.use(package_desc)

var p = newParser:
  # option("-d", "--depsdir", default=some("pkger"), help="Directory where pkger will keep deps")
  command("init"):
    run:
      cmd_init(getCurrentDir())
  command("use"):
    help("Add a package to this project.")
    flag("--no-deps", help="If provided, don't also add the packages deps")
    arg("package", help="package, package@version, package@sha, ./localpath, https://github.com/path/to/repo@sha, etc...")
    run:
      cmd_use(pkgerContext(), opts.package)
  command("fetch"):
    help("Fetch all the external packages that are missing")
    run:
      cmd_fetch(pkgerContext())
  command("low"):
    command("updatepackagelist"):
      run:
        var ctx = pkgerContext()
        cmd_updatepackagelist(ctx)

proc cli*(args: seq[string]) =
  try:
    p.run(args)
  except UsageError as e:
    stderr.writeLine getCurrentExceptionMsg()
    raise  

when isMainModule:
  addHandler(newConsoleLogger())
  cli(commandLineParams())
