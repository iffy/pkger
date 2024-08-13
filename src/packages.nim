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
import std/sha1
import std/uri

import ./context
import ./objs
import ./commandline
import ./nimblefiles
import ./deps

#-----------------------------------------------------------------
# Package registry
#-----------------------------------------------------------------
const PACKAGES_REPO_URL = when defined(testmode):
    currentSourcePath().parentDir()/"../tests/data/packagesrepo"
  else:
    "https://github.com/nim-lang/packages"

proc packages_repo_dir(ctx: PkgerContext): string =
  relativePath(ctx.depsDir / "_packages", ctx.workDir)

proc updatePackagesRepo(ctx: PkgerContext) =
  ## Download the latest packages.json repo
  let packages_dir = ctx.packages_repo_dir()
  if not packages_dir.dirExists:
    # initial clone
    runsh(@["git", "clone", PACKAGES_REPO_URL, packages_dir])
  else:
    # update existing clone?
    runsh(@["git", "fetch", "origin"], workingDir = packages_dir)
    runsh(@["git", "reset", "--hard", "FETCH_HEAD"], workingDir = packages_dir)

proc lookupPackageFromRegistry*(ctx: PkgerContext, name: string): Option[ReqSource] =
  ## Get package info for a particular package
  let packages_json = ctx.packages_repo_dir()/"packages.json"
  if not packages_json.fileExists():
    ctx.updatePackagesRepo()
  if not packages_json.fileExists():
    raise ValueError.newException("Failed to get packages repo")
  let data = parseJson(newFileStream(packages_json, fmRead))
  for item in data:
    let thisname = item{"name"}.getStr()
    if thisname == name:
      let meth = item{"method"}.getStr()
      let depkind = case meth
        of "git": fmGitRepo
        of "hg": fmHgRepo
        else: fmUnknown
      return some((
        url: item{"url"}.getStr(),
        kind: depkind,
      ))

proc updatePackagesDir*(ctx: PkgerContext) =
  ## Download the latest packages.json data
  updatePackagesRepo(ctx)

proc packageDownloadDir*(ctx: PkgerContext): string =
  ctx.depsDir/"lazy"

proc nameFromURL*(ctx: PkgerContext, url: string): string =
  let pinned = ctx.getPinnedReqs()
  for req in pinned:
    if req.src.url == url:
      return req.pkgname
  
  let data = parseJson(newFileStream(ctx.packages_repo_dir()/"packages.json", fmRead))
  for item in data:
    let thisurl = item{"url"}.getStr()
    if thisurl == url:
      return item{"name"}.getStr()

#-----------------------------------------------------------------
# Git stuff
#-----------------------------------------------------------------
proc urlToDirname*(url: string): string =
  let parsed = parseUri(url)
  if parsed.path != "":
    result = parsed.path.split("/")[^1]
  else:
    result = parsed.hostname
  result &= "-" & $secureHash(url)

proc gitGetSHA*(repodir: string, commitish: string): Option[string] =
  try:
    let (outp, rc) = execCmdEx("git rev-parse " & quoteShell(commitish),
      options = {poUsePath},
      workingDir = repodir)
    if rc == 0:
      return some(outp.strip())
  except:
    discard

proc gitThingExists*(repodir: string, commitish: string): bool =
  ## Return true if the commitish exists
  gitGetSHA(repodir, commitish).isSome()

proc gitSearchForCommitish*(repodir: string, version: string): string =
  if repodir.gitThingExists(version):
    return version
  if version.startsWith("v"):
    let unv = version.strip(chars={'v'}, leading = true, trailing = false)
    if repodir.gitThingExists(unv):
      return unv
  if repodir.gitThingExists("origin/" & version):
    return "origin/" & version

proc cacheGitRepo*(ctx: PkgerContext, url: string, resetToVersion = ""): string =
  ## Clone a git repo if it doesn't exist and return the path to the repo on disk
  let cachedir = ctx.depsDir/"_cache"
  createDir(cachedir)
  let repodir = cachedir/urlToDirname(url)
  result = repodir
  if dirExists(repodir):
    if resetToVersion != "":
      runsh(@["git", "fetch", "origin"], workingDir = repodir)  
  else:
    runsh(@["git", "clone", url, repodir])
  if resetToVersion != "":
    var version = repodir.gitSearchForCommitish(resetToVersion)
    runsh(@["git", "reset", "--hard", version], workingDir = repodir)

proc placeGitRepo*(ctx: PkgerContext, url: string, dstdir: string, resetToVersion = "") =
  ## Ensure that a git repo exists at dstdir, using the available cached git repo if present
  if dirExists(dstdir):
    if resetToVersion != "":
      let sha = try:
          runshout(@["git", "rev-parse", "HEAD"], workingDir = dstdir).strip()
        except: ""
      if sha == resetToVersion:
        return
    else:
      return
  let srcdir = ctx.cacheGitRepo(url, resetToVersion)
  info "cp -R " & relativePath(srcdir, ".") & " " & relativePath(dstdir, ".")
  copyDirWithPermissions(srcdir, dstdir)

proc readGitSha*(repodir: string): string =
  runshout(@["git", "rev-parse", "HEAD"], workingDir = repodir).strip()

#-----------------------------------------------------------------
# Parsing and serializing
#-----------------------------------------------------------------
proc parseNumericVersion*(x: string): NumericVersion =
  x.split(".").mapIt(parseInt(it)).NumericVersion

proc `$`*(x: NumericVersion): string =
  toSeq(x.distinctBase.mapIt($it)).join(".")

proc `$`*(x: Version): string =
  case x.kind
  of vSHA:
    x.sha
  of vAnyVersion:
    ""
  of vNumeric:
    $x.nver
  of vRange:
    x.vrange

proc nice*(x: InstalledPackage): string =
  result = x.name
  if x.version != "":
    result &= " " & x.version
  if x.sha != "":
    result &= " " & x.sha

proc parseVersion*(x: string): Version =
  ## Parse a string description of a version
  if x == "":
    return Version(kind: vAnyVersion)
  else:
    try:
      return Version(kind: vNumeric, nver: parseNumericVersion(x))
    except:
      return Version(kind: vSHA, sha: x)

proc parse*(x: ReqNimbleDesc): ParsedNimbleReq =
  let d = x.string.strip()
  if ":" in d:
    # url
    let parts = d.split(seps={'#','@'}, 1)
    let url = parts[0]
    let version = if parts.len > 1:
        parts[1]
      else:
        ""
    return ParsedNimbleReq(
      isUrl: true,
      url: url,
      version: version,
    )
  else:
    let (name, version) = d.splitNimbleNameAndVersion()
    return ParsedNimbleReq(
      isUrl: false,
      name: name,
      version: version,
    )

proc pin*(req: Req, sha: string): PinnedReq =
  (
    pkgname: req.pkgname,
    parent: req.parent,
    src: req.src,
    sha: sha,
  )

proc toReq*(pinned: PinnedReq): Req =
  (
    pkgname: pinned.pkgname,
    parent: pinned.parent,
    src: pinned.src,
    version: Version(kind: vSHA, sha: pinned.sha),
  )

proc toReq*(ctx: PkgerContext, reqdesc: ReqDesc, parent: string): Req =
  ## Parse a string requirement description into a Requirement
  ## `parent` should be "" if this requirement is a base requirement
  ## otherwise it should be the name of the pkg requiring this
  let desc = reqdesc.string
  let parts = desc.split("@", 1)
  let name_or_url = parts[0]
  let version = parseVersion(if parts.len > 1: parts[1] else: "")
  if dirExists(name_or_url):
    # localpath
    let pkgname = getProjectNameFromNimble(name_or_url)
    return (
      pkgname: pkgname,
      parent: parent,
      src: (
        url: relativePath(name_or_url, ctx.rootDir),
        kind: fmLocalFile,
      ),
      version: version
    )
  
  # Check package registry
  let o = ctx.lookupPackageFromRegistry(name_or_url)
  if o.isSome:
    let pkgsrc = o.get()
    return (
      pkgname: name_or_url,
      parent: parent,
      src: pkgsrc,
      version: version,
    )
  
  # Try git
  let isGit = block:
    let parsed = parseUri(name_or_url)
    if "git" in parsed.hostname or name_or_url.endsWith(".git"):
      true
    else:
      try:
        discard execProcess("git", args = @["ls-remote", "--tags", name_or_url],
          options={poUsePath})
        true
      except:
        false
  if isGit:
    let git_repo_path = ctx.cacheGitRepo(name_or_url)
    let pkgname = getProjectNameFromNimble(git_repo_path)
    return (
      pkgname: pkgname,
      parent: parent,
      src: (
        url: name_or_url,
        kind: fmGitRepo,
      ),
      version: version
    )
 
  raise ValueError.newException("Mercurial not yet supported")

proc toReq*(ctx: PkgerContext, reqdesc: ReqNimbleDesc, parent: string): Req =
  let parsed = reqdesc.parse()
  case parsed.isUrl
  of true:
    var desc = parsed.url
    if parsed.version != "":
      desc &= "@" & parsed.version
    return ctx.toReq(desc.ReqDesc, parent)
  of false:
    # not a URL
    var req = ctx.toReq(parsed.name.ReqDesc, parent)
    if parsed.version != "":
      req.version = Version(kind: vRange, vrange: parsed.version)
    return req
    

proc ondiskPath*(ctx: PkgerContext, req: Req): string =
  ## Return the path to where the source code is/should be
  case req.src.kind
  of fmUnknown:
    raise ValueError.newException("Can't choose path for unknown dep type: " & $req)
  of fmLocalFile:
    return ctx.rootDir/req.src.url
  of fmGitRepo, fmHgRepo:
    return ctx.depsDir/"lazy"/req.pkgname 


proc ensurePresent*(ctx: PkgerContext, req: Req): PinnedReq =
  ## Put code for a single package in place
  case req.src.kind
  of fmUnknown:
    raise ValueError.newException("Can't fetch: " & $req)
  of fmLocalFile:
    if not dirExists(req.src.url):
      raise ValueError.newException("Local package missing: " & $req)
    return req.pin("")
  of fmGitRepo:
    let path = ctx.ondiskPath(req)
    var resetToVersion = case req.version.kind
      of vNumeric:
        "v" & $req.version.nver
      of vSHA:
        req.version.sha
      of vAnyVersion:
        ""
      of vRange:
        ""
    ctx.placeGitRepo(req.src.url, path, resetToVersion)
    return req.pin(readGitSha(path))
  of fmHgRepo:
    raise ValueError.newException("Mercurial not yet supported")

# proc placePackage*(ctx: PkgerContext, package_desc: string, dstdir: string): Dep =
#   ## Install a package@version in dstdir/{package}
#   let o = ctx.locatePackage(package_desc)
#   if o.isNone:
#     raise ValueError.newException("package not found: " & package_desc)
#   let vdep = o.get()
#   ctx.fetch(vdep.dep, some(vdep.version))

proc getNimPathsFromProject*(dirname: string): seq[string] =
  ## Return what should be set as --path:X to add the given package
  ## to the path.
  for nimblefile in findNimbleFiles(dirname):
    let data = parseNimbleFile(nimblefile)
    result.add(data.srcDir)

proc installedPackages*(ctx: PkgerContext): seq[InstalledPackage] =
  for pin in ctx.getPinnedReqs():
    let path = ctx.ondiskPath(pin.toReq())
    if not dirExists(path):
      continue
    let version = try:
        getVersionFromNimble(path)
      except:
        ""
    result.add((
      name: pin.pkgname,
      version: version,
      sha: pin.sha,
    ))

proc allReqs*(ctx: PkgerContext): seq[RawReq] =
  ## List all known requirements (without fetching anything) for this project
  var packagesToProcess = @[(ctx.rootDir, "")]
  for pin in ctx.getPinnedReqs():
    let path = ctx.ondiskPath(pin.toReq())
    if dirExists(path):
      packagesToProcess.add((path, pin.parent))
  while packagesToProcess.len > 0:
    let (path, parent) = packagesToProcess.pop()
    for reqdesc in listNimbleRequires(path):
      let ndesc = reqdesc.ReqNimbleDesc.parse()
      if ndesc.isUrl:
        result.add((
          name: ctx.nameFromURL(ndesc.url),
          label: ndesc.url,
          parent: parent,
          version: ndesc.version,
        ))
      else:
        if ndesc.name == "nim":
          continue
        result.add((
          name: ndesc.name,
          label: ndesc.name,
          parent: parent,
          version: ndesc.version,
        ))
    
