import std/json
import std/os
import std/strutils

import ./context
import ./objs

proc `%`*(x: ReqSource): JsonNode =
  %* {
    "url": x.url,
    "kind": x.kind,
  }

proc `%`*(x: PinnedReq): JsonNode =
  %* {
    "pkgname": x.pkgname,
    "parent": x.parent,
    "src": x.src,
    "sha": x.sha,
  }

proc readDepsFile(ctx: PkgerContext): JsonNode =
  try:
    parseJson(readFile(ctx.depsDir/"deps.json"))
  except:
    %* {
      "pinned": {}
    }

proc writeDepsFile(ctx: PkgerContext, data: JsonNode) =
  writeFile(ctx.depsDir/"deps.json", data.pretty())

proc getPinnedReqs*(ctx: PkgerContext): seq[PinnedReq] =
  let data = readDepsFile(ctx)
  for name in data["pinned"].keys():
    let item = data["pinned"][name]
    result.add(to(item, PinnedReq))

proc setPinnedReqs*(ctx: PkgerContext, pinned: seq[PinnedReq]) =
  var data = readDepsFile(ctx)
  data["pinned"] = newJObject()
  for req in pinned:
    data["pinned"][req.pkgname] = %req
  ctx.writeDepsFile(data)

proc add*(ctx: PkgerContext, req: seq[PinnedReq]) =
  var existing = ctx.getPinnedReqs()
  existing.add(req)
  ctx.setPinnedReqs(existing)
