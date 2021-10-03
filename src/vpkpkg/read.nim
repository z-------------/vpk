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
import std/os
import std/strutils
import std/md5
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
  VpkArchiveMd5Entry = object
    archiveIndex: uint32
    startingOffset: uint32
    count: uint32
    md5Checksum: array[16, byte]
  VpkOtherMd5Entry = object
    treeChecksum: array[16, byte]
    archiveMd5SectionChecksum: array[16, byte]
  VpkCheckHashResult* = tuple[result: bool; message: string]

func fileDataOffset*(header: VpkHeader): uint32 =
  header.endOffset.uint32 + header.treeSize

func totalLength*(dirEntry: VpkDirectoryEntry): uint32 =
  dirEntry.preloadBytes + dirEntry.entryLength

# read directory #

func getArchiveFilename*(v: Vpk; archiveIndex: uint32): string =
  const Suffix = "_dir"
  let
    (dir, name, extension) = splitFile(v.filename)
    suffixIdx = name.find(Suffix)
  if suffixIdx == -1 or suffixIdx + Suffix.len != name.len:
    raise newException(CatchableError, "filename of current VPK does not end with \"_dir\"")
  let
    nameBase = name[0..suffixIdx] # incl. '_'
    indexStr = ($archiveIndex).align(3, '0') # TODO is it always 3?
  dir / nameBase & indexStr & extension

proc readHeader*(f: File): VpkHeader =
  result.signature = f.read(uint32)
  if result.signature != 0x55aa1234:
    raise newException(CatchableError, "invalid VPK file: wrong file signature: 0x" & $result.signature.toHex())
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

# TODO support "skipping"?
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

proc readVpk*(f: File; filename: string): Vpk =
  result.f = f
  result.filename = filename
  result.header = readHeader(f)
  result.entries = readDirectory(f)

proc readVpk*(filename: string): Vpk =
  let f = open(filename, fmRead)
  readVpk(f, filename)

# read files #

proc readFile*(v: Vpk; dirEntry: VpkDirectoryEntry; outBuf: pointer; outBufLen: uint32) =
  var p = 0'u32

  if dirEntry.preloadBytes != 0:
    v.f.setFilePos(dirEntry.endOffset)
    v.f.readBufferStrict(outBuf, min(dirEntry.preloadBytes.uint32, outBufLen))
    p += dirEntry.preloadBytes

  let (archiveFile, offset) =
    if dirEntry.archiveIndex == 0x7fff:
      (v.f, v.header.fileDataOffset + dirEntry.entryOffset)
    else:
      (open(v.getArchiveFilename(dirEntry.archiveIndex), fmRead), dirEntry.entryOffset)
  archiveFile.setFilePos(offset.int64)
  archiveFile.readBufferStrict(outBuf +@ p, min(dirEntry.entryLength, outBufLen - p))

# check hashes #

proc readArchiveMd5Entry(f: File): VpkArchiveMd5Entry =
  result.archiveIndex = f.read(uint32)
  result.startingOffset = f.read(uint32)
  result.count = f.read(uint32)
  result.md5Checksum = f.read(type(result.md5Checksum))

template hashCheckHeaderVersion(header: VpkHeader): untyped =
  if header.version != 2:
    raise newException(CatchableError, "only VPK 2 supports hash checking")

proc checkArchiveHashes*(v: Vpk): VpkCheckHashResult =
  hashCheckHeaderVersion(v.header)
  let
    sectionOffset = v.header.fileDataOffset + v.header.fileDataSectionSize
    count = v.header.archiveMd5SectionSize div 28 # each entry is 28 bytes long
  if count == 0:
    return (true, "no archive hashes to check")
  var archiveEntries: Table[uint32, seq[VpkArchiveMd5Entry]]
  v.f.setFilePos(sectionOffset.int64)
  for i in 0..<count:
    let entry = readArchiveMd5Entry(v.f)
    if not archiveEntries.hasKey(entry.archiveIndex):
      archiveEntries[entry.archiveIndex] = newSeq[VpkArchiveMd5Entry]()
    archiveEntries[entry.archiveIndex].add(entry)
  for archiveIndex in archiveEntries.keys:
    let archiveFile = open(v.getArchiveFilename(archiveIndex), fmRead)
    for entry in archiveEntries[archiveIndex]:
      archiveFile.setFilePos(entry.startingOffset.int64)
      var dataChunk = newString(entry.count)
      archiveFile.readBufferStrict(addr dataChunk[0], entry.count)
      if toMd5(dataChunk) != entry.md5Checksum:
        return (false, "hash validation failed for archive " & $archiveIndex & " at offset " & $entry.startingOffset & ", length " & $entry.count)
  (true, "")

proc readOtherMd5Entry*(f: File): VpkOtherMd5Entry =
  result.treeChecksum = f.read(type(result.treeChecksum))
  result.archiveMd5SectionChecksum = f.read(type(result.archiveMd5SectionChecksum))

proc checkOtherHashes(v: Vpk): VpkCheckHashResult =
  hashCheckHeaderVersion(v.header)

  let
    archiveMd5SectionOffset = v.header.fileDataOffset + v.header.fileDataSectionSize
    sectionOffset = archiveMd5SectionOffset + v.header.archiveMd5SectionSize
  v.f.setFilePos(sectionOffset.int64)
  let entry = readOtherMd5Entry(v.f)

  # tree
  v.f.setFilePos(v.header.endOffset)
  var treeData = newString(v.header.treeSize)
  v.f.readBufferStrict(addr treeData[0], v.header.treeSize)
  if toMd5(treeData) != entry.treeChecksum:
    return (false, "hash validation failed for tree")

  # archive md5 section
  v.f.setFilePos(archiveMd5SectionOffset.int64)
  var archiveMd5SectionData = newString(v.header.archiveMd5SectionSize)
  v.f.readBufferStrict(addr archiveMd5SectionData[0], v.header.archiveMd5SectionSize)
  if toMd5(archiveMd5SectionData) != entry.archiveMd5SectionChecksum:
    return (false, "hash validation failed for archive MD5 section")

  (true, "")

proc checkHashes*(v: Vpk): VpkCheckHashResult =
  let archiveResult = v.checkArchiveHashes()
  if not archiveResult.result:
    return archiveResult

  let otherResult = v.checkOtherHashes()
  if not otherResult.result:
    return otherResult

  (true, "")
