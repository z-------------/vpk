# Copyright (C) 2021 Zack Guard
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

import zvpkpkg/read

export read

when isMainModule:
  import std/os
  import std/parseopt
  import std/options
  import std/tables

  template die(msg: string; status = 1) =
    stderr.writeLine(msg)
    quit(status)

  proc parseParams(params: seq[string]): tuple[opts: Table[string, string]; args: seq[string]] =
    var optParser = initOptParser(params)
    for kind, key, val in optParser.getopt:
      case kind
      of cmdArgument:
        result.args.add(key)
      else:
        result.opts[key] = val

  let
    params = parseParams(commandLineParams())
    filename =
      if params.args.len > 0:
        params.args[0]
      else:
        die("no filename specified")
    entryName =
      if params.args.len > 1:
        params.args[1].some
      else:
        none(string)
    isCheckHashes = params.opts.hasKey("check-hashes")
  var v: Vpk
  try:
    v = readVpk(filename)
  except IOError as e:
    stderr.writeLine(e.msg)
    quit(QuitFailure)

  if entryName.isSome:
    let entry = v.entries[entryName.get]
    if entry.totalLength > 0:
      var fileBuf = newString(entry.totalLength)
      v.readFile(entry, addr fileBuf[0], entry.totalLength)
      stdout.write(fileBuf)
  else:
    for fullpath in v.entries.keys:
      echo fullpath
    if isCheckHashes:
      let (checkResult, checkMessage) = v.checkHashes()
      if not checkResult:
        stderr.writeLine("Hash check failed: " & checkMessage)
