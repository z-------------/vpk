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

import vpkpkg/parse
import std/os

export parse

when isMainModule:
  import std/strutils
  import std/strformat
  import std/sugar

  doAssert paramCount() >= 1
  let
    filename = paramStr(1)
    f = open(filename, fmRead)
  let data = readVpk(f)

  # echo data.header
  # for fullpath, entry in data.entries.pairs:
  #   echo fullpath, ": ", entry

  let entry = data.entries[paramStr(2)]
  var fileBuf = newSeq[byte](entry.totalLength)
  f.readFile(data.header, entry, addr fileBuf[0], entry.totalLength)
  for c in fileBuf:
    echo c.char
