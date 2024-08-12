# pkger

A good enough Nim package manager.

## Why?

Some of these things might get fixed in [`nimble`](https://github.com/nim-lang/nimble) and [`atlas`](https://github.com/nim-lang/atlas), but until then:

- `nimble lock` doesn't work well for cross-platform projects when there are platform-specific dependencies.
- `atlas` can't install specific versions of packages
- I just want library code, not the binaries built as a result of `nimble install ...`

## Philosophy

I like how `atlas` manages files within the "workspace" directory and updates `nim.cfg` to get paths set up. `pkger` does the same thing.

Also, `nimble` and `atlas` have an advanced SAT solver for installing the right versions of things. This doesn't. You are the SAT solver, because 99% of the time, you can do a great job. `pkger status` will guide you to pick the right versions, but if you want a "broken" set of packages, you totally can.

## Installation

```
nimble install https://github.com/iffy/pkger/
```

## Usage

Initialize `pkger` use in a project with

```
pkger init
```

And then you'll go through iterations of checking what dependencies need to be installed (as defined in `.nimble` files) and installing the version you want.

### Check for unmet dependencies

```
pkger status
```

### Use a package from the nimble directory

```
# any version
pkger use keyring

# specific version
pkger use keyring@0.4.2

# specific Git SHA
pkger use keyring@811a2d0d77221f1077e060e802dc681cfa2e8d6e
```

### Use a package on the local disk

```
pkger use ../path/to/somepackage
```

### Use a package from a Git repo

```
# any version
pkger use https://github.com/iffy/nim-keyring

# specific version
pkger use https://github.com/iffy/nim-keyring@0.4.2

# specific Git SHA
pkger use https://github.com/iffy/nim-keyring@811a2d0d77221f1077e060e802dc681cfa2e8d6e
```

### Fetch missing source files

```
pkger fetch
```