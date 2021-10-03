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

import vpkpkg/read

export read

when isMainModule:
  import std/os

  doAssert paramCount() >= 1
  let
    filename = paramStr(1)
    v = readVpk(filename)

  if paramCount() >= 2:
    let
      entryName = paramStr(2)
      entry = v.entries[entryName]
    if entry.totalLength > 0:
      var fileBuf = newString(entry.totalLength)
      v.readFile(entry, addr fileBuf[0], entry.totalLength)
      echo fileBuf
  else:
    echo v.header
    for fullpath in v.entries.keys:
      echo fullpath
