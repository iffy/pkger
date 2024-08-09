import std/json
import std/logging
import std/options
import std/osproc
import std/os
import std/sequtils
import std/streams
import std/strformat
import std/strutils
import std/tempfiles
import std/typetraits
import std/uri

import ./context
import ./objs
import ./commandline
import ./nimblefiles

const PACKAGES_REPO_URL = when defined(testmode):
    currentSourcePath().parentDir()/"../tests/data/packagesrepo"
  else:
    "https://github.com/nim-lang/packages"

proc packages_repo_dir(ctx: PkgerContext): string =
  relativePath(ctx.depsDir / "packages", ctx.workDir)

proc updatePackagesRepo(ctx: PkgerContext) =
  ## Download the latest packages.json repo
  let packages_dir = ctx.packages_repo_dir()
  if not packages_dir.dirExists:
    # initial clone
    runsh(@["git", "clone", PACKAGES_REPO_URL, packages_dir])
  else:
    # update existing clone?
    runsh(@["git", "fetch", "origin"], workingDir = packages_dir)
    runsh(@["git", "merge", "origin/master"], workingDir = packages_dir)

proc getPackage*(ctx: PkgerContext, name: string): Option[Dep] =
  ## Get package info for a particular package
  let data = parseJson(newFileStream(ctx.packages_repo_dir()/"packages.json", fmRead))
  for item in data:
    let thisname = item{"name"}.getStr()
    if thisname == name:
      let meth = item{"method"}.getStr()
      let depkind = case meth
        of "git": fmGitRepo
        of "hg": fmHgRepo
        else: fmUnknown
      return some((
        name: thisname,
        url: item{"url"}.getStr(),
        kind: depkind,
        sha: "",
      ))

proc updatePackagesDir*(ctx: PkgerContext) =
  ## Download the latest packages.json data
  updatePackagesRepo(ctx)

proc packageDownloadDir*(ctx: PkgerContext): string =
  ctx.depsDir/"lazy"

proc ondiskPath*(ctx: PkgerContext, dep: Dep): string =
  ## Return the path to where the source code is/should be
  case dep.kind
  of fmUnknown:
    raise ValueError.newException("Can't choose path for unknown dep type: " & $dep)
  of fmLocalFile:
    return ctx.rootDir/dep.url
  of fmGitRepo, fmHgRepo:
    return ctx.depsDir/"lazy"/dep.name 

proc parseNumericVersion*(x: string): NumericVersion =
  x.split(".").mapIt(parseInt(it)).NumericVersion

proc `$`*(x: NumericVersion): string =
  toSeq(x.distinctBase.mapIt($it)).join(".")

proc `$`*(x: Version): string =
  case x.kind
  of vVCS:
    x.sha
  of vLatest:
    ""
  of vNumeric:
    $x.nver

proc parseVersion*(x: string): Version =
  ## Parse a string description of a version
  if x == "":
    return Version(kind: vLatest)
  else:
    try:
      return Version(kind: vNumeric, nver: parseNumericVersion(x))
    except:
      return Version(kind: vVCS, sha: x)

proc locatePackage*(ctx: PkgerContext, package_desc: string): Option[DepAndVersion] =
  ## Figure out *how* to get the given package
  let parts = package_desc.split("@", 1)
  let name_or_url = parts[0]
  let version = parseVersion(if parts.len > 1: parts[1] else: "")
  if dirExists(name_or_url):
    # localpath
    var name = name_or_url
    for nimblefile in findNimbleFiles(name_or_url):
      let data = parseNimbleFile(nimblefile)
      if data.name != "":
        name = data.name
    return some((
      (
        name: name,
        url: relativePath(name_or_url, ctx.rootDir),
        kind: fmLocalFile,
        sha: "",
      ),
      Version(kind: vLatest),
    ))
  else:
    # is it in the package index?
    let o = ctx.getPackage(name_or_url)
    if o.isSome:
      return some((o.get(), version))
    # it's either a URL or it's invalid
    var isGit = false
    try:
      discard execProcess("git", args = @["ls-remote", "--tags", name_or_url],
        options={poUsePath})
      isGit = true
    except:
      discard
    
    if isGit:
      let tmpd = createTempDir("pkger", "clone")
      try:
        runsh(@["git", "clone", name_or_url, tmpd])
        let name = getProjectNameFromNimble(tmpd)
        let dep = (
          name: name,
          url: name_or_url,
          kind: fmGitRepo,
          sha: "",
        )
        let ondisk = ctx.ondiskPath(dep)
        if not dirExists(ondisk):
          ondisk.parentDir.createDir()
          info &"mv {tmpd} {ondisk}"
          moveDir(tmpd, ondisk)
        return some((dep, version))
      finally:
        removeDir(tmpd)
    
    TODO "handle hg locating"

proc gitClonePackage*(ctx: PkgerContext, dep: Dep, version: Version, dstdir: string): Dep =
  ## Clone a repo, set it to the desired version then return the SHA
  doAssert dep.kind == fmGitRepo
  if dirExists(dstdir):
    runsh(@["git", "fetch", "origin"], workingDir = dstdir)
  else:
    runsh(@["git", "clone", dep.url, relativePath(dstdir, ctx.workDir)])

  # Move to the right version
  case version.kind
  of vLatest:
    discard "It's already at the latest version"
  of vVCS:
    runsh(@["git", "reset", "--hard", version.sha], workingDir = dstdir)
  of vNumeric:
    runsh(@["git", "reset", "--hard", "v" & $version.nver], workingDir = dstdir)
  
  # Get the resulting SHA
  let sha = runshout(@["git", "rev-parse", "HEAD"], workingDir = dstdir).strip()
  return (
    name: dep.name,
    url: dep.url,
    kind: dep.kind,
    sha: sha,
  )

proc fetch*(ctx: PkgerContext, dep: Dep, version = none[Version]()): Dep =
  ## Put code for a single package in place
  case dep.kind
  of fmUnknown:
    TODO "Handle unknown package type"
  of fmLocalFile:
    # It's local and already fetched. And if it isn't, pkger doesn't manage it anyway.
    return dep
  of fmGitRepo:
    let path = ctx.ondiskPath(dep)
    let ver = if version.isSome:
        version.get()
      elif dep.sha != "":
        Version(kind: vVCS, sha: dep.sha)
      else:
        Version(kind: vLatest)
    return ctx.gitClonePackage(dep, ver, path)
  of fmHgRepo:
    TODO "Handle Mercurial"

proc placePackage*(ctx: PkgerContext, package_desc: string, dstdir: string): Dep =
  ## Install a package@version in dstdir/{package}
  let o = ctx.locatePackage(package_desc)
  if o.isNone:
    raise ValueError.newException("package not found: " & package_desc)
  let vdep = o.get()
  ctx.fetch(vdep.dep, some(vdep.version))

proc getNimPathsFromProject*(dirname: string): seq[string] =
  ## Return what should be set as --path:X to add the given package
  ## to the path.
  TODO "Handle the case where the project uses pkger instead of nimble"

  for nimblefile in findNimbleFiles(dirname):
    let data = parseNimbleFile(nimblefile)
    result.add(data.srcDir)