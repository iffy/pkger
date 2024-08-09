import std/json
import std/os
import std/strutils

import ./context
import ./objs

proc `%`*(x: Dep): JsonNode =
  %* {
    "name": x.name,
    "url": x.url,
    "kind": x.kind,
    "sha": x.sha,
  }

proc readDepsFile(ctx: PkgerContext): JsonNode =
  try:
    parseJson(readFile(ctx.depsDir/"deps.json"))
  except:
    %* {
      "deps": {}
    }

proc writeDepsFile(ctx: PkgerContext, data: JsonNode) =
  writeFile(ctx.depsDir/"deps.json", data.pretty())

proc getDeps*(ctx: PkgerContext): seq[Dep] =
  let data = readDepsFile(ctx)
  for name in data["deps"].keys():
    let item = data["deps"][name]
    result.add((
      name: item{"name"}.getStr(),
      url: item{"url"}.getStr(),
      kind: parseEnum[DepKind](item{"kind"}.getStr()),
      sha: item{"sha"}.getStr(),
    ))

proc setDeps*(ctx: PkgerContext, deps: seq[Dep]) =
  var data = readDepsFile(ctx)
  data["deps"] = newJObject()
  for dep in deps:
    data["deps"][dep.name] = %dep
  ctx.writeDepsFile(data)

proc addNewDeps*(ctx: PkgerContext, dep: seq[Dep]) =
  var existing = ctx.getDeps()
  existing.add(dep)
  ctx.setDeps(existing)
