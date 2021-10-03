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
import ./streamutils

export tables

template empty[T](a: openArray[T]): bool =
  a.len == 0

type
  Vpk* = object
    header*: VpkHeader
    entries*: Table[string, VpkDirectoryEntry]
    filename*: string
    f: File
  VpkHeader* = object
    # common
    signature*: uint32
    version*: uint32
    treeSize*: uint32
    # v2 only
    fileDataSectionSize*: uint32
    archiveMd5SectionSize*: uint32
    otherMd5SectionSize*: uint32
    signatureSectionSize*: uint32

    endOffset*: int64 # offset of the end of the header
  VpkDirectoryEntry* = object
    crc*: uint32
    preloadBytes*: uint16
    archiveIndex*: uint16
    entryOffset*: uint32
    entryLength*: uint32
    endOffset*: int64 # offset of the end of this entry

func fileDataOffset*(header: VpkHeader): uint32 =
  header.endOffset.uint32 + header.treeSize

func totalLength*(dirEntry: VpkDirectoryEntry): uint32 =
  dirEntry.preloadBytes + dirEntry.entryLength

proc readHeader*(f: File): VpkHeader =
  result.signature = f.read(uint32)
  result.version = f.read(uint32)
  if result.version notin {1, 2}:
    raise newException(CatchableError, "invalid version: " & $result.version)
  result.treeSize = f.read(uint32)

  if result.version == 2:
    result.fileDataSectionSize = f.read(uint32)
    result.archiveMd5SectionSize = f.read(uint32)
    result.otherMd5SectionSize = f.read(uint32)
    result.signatureSectionSize = f.read(uint32)

  result.endOffset = f.getFilePos()

proc readDirectoryEntry*(f: File): VpkDirectoryEntry =
  result.crc = f.read(uint32)
  result.preloadBytes = f.read(uint16)
  result.archiveIndex = f.read(uint16)
  result.entryOffset = f.read(uint32)
  result.entryLength = f.read(uint32)
  if f.read(uint16) != 0xffff:
    raise newException(CatchableError, "expected terminator")

  result.endOffset = f.getFilePos()

func buildFullPath(extension, path, filename: string): string =
  if path != " ":
    result.add(path)
    result.add('/')
  if filename != " ":
    result.add(filename)
  if extension != " ":
    result.add('.')
    result.add(extension)

proc readDirectory*(f: File): Table[string, VpkDirectoryEntry] =
  while true:
    let extension = f.readString()
    if extension.empty:
      break
    while true:
      let path = f.readString()
      if path.empty:
        break
      while true:
        let filename = f.readString()
        if filename.empty:
          break
        let
          fullPath = buildFullPath(extension, path, filename)
          entry = readDirectoryEntry(f)
        result[fullpath] = entry
        f.setFilePos(entry.preloadBytes.int64, fspCur)

proc readFile*(v: Vpk; dirEntry: VpkDirectoryEntry; outBuf: pointer; outBufLen: uint32) =
  var p = 0'u32

  if dirEntry.preloadBytes != 0:
    v.f.setFilePos(dirEntry.endOffset)
    v.f.readBufferStrict(outBuf, min(dirEntry.preloadBytes.uint32, outBufLen))
    p += dirEntry.preloadBytes

  if dirEntry.archiveIndex == 0x7fff:
    v.f.setFilePos((v.header.fileDataOffset + dirEntry.entryOffset).int64)
    v.f.readBufferStrict(outBuf +@ p, min(dirEntry.entryLength, outBufLen - p))
  else:
    raise newException(CatchableError, "file data in separate files is not supported")

proc readVpk*(f: File; filename: string): Vpk =
  result.f = f
  result.filename = filename
  result.header = readHeader(f)
  if result.header.version == 2:
    raise newException(CatchableError, "VPK 2 is not supported")
  result.entries = readDirectory(f)

proc readVpk*(filename: string): Vpk =
  let f = open(filename, fmRead)
  readVpk(f, filename)
