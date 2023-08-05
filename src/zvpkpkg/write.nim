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

import std/tables
from std/os import splitFile
import ./consts
import ./streamutils

export tables

func splitEntryFilename(path: string): tuple[extension, path, filename: string] =
  let (dir, name, ext) = splitFile(path)
  result.extension = if ext == "": " " else: ext[1..ext.high]
  result.path = if dir == "": " " else: dir
  result.filename = if name == "": " " else: name

proc writeDirectoryEntry(f: File; fn: string) =
  f.writeBytes(0'u32) # XXX crc
  f.writeBytes(0'u16) # XXX preloadBytes
  f.writeBytes(SameFileArchiveIndex)
  f.writeBytes(0'u32) # XXX entryOffset
  f.writeBytes(0'u32) # XXX entryLength
  f.writeBytes(DirectoryEntryTerminator)

template writeString(f: File; s: string) =
  f.write(s)
  f.write('\0')

proc write*(f: File; entries: openArray[string]; preloadBytes: int) =
  # write header
  f.writeBytes(MagicNumber)
  f.writeBytes(1'u32) # VPK version
  let treeSizePos = f.getFilePos()
  f.writeBytes(0'u32) # placeholder for tree size which we don't know yet

  # build tree
  var tree: Table[string, Table[string, Table[string, string]]]
  for fn in entries:
    let (extension, path, filename) = splitEntryFilename(fn)
    discard tree.hasKeyOrPut(extension, initTable[string, Table[string, string]]())
    discard tree[extension].hasKeyOrPut(path, initTable[string, string]())
    tree[extension][path][filename] = fn

  # write tree
  let treeStartPos = f.getFilePos()
  for (extension, pathTree) in tree.pairs:
    f.writeString(extension)
    for (path, filenameTree) in pathTree.pairs:
      f.writeString(path)
      for (filename, fn) in filenameTree.pairs:
        f.writeString(filename)
        writeDirectoryEntry(f, fn)
      f.writeString("")
    f.writeString("")
  f.writeString("")
  let treeEndPos = f.getFilePos()

  # write tree size
  f.setFilePos(treeSizePos)
  f.writeBytes(uint32(treeEndPos - treeStartPos))

when isMainModule:
  let f = open("test.vpk", fmWrite)
  f.write(entries = ["foo/bar.baz", "addoninfo.txt", "qux/stuff/hi.baz"], preloadBytes = 16)
  f.close()
