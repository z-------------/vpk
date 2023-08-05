# vpk

Read VPK files in Nim. See also the command-line counterpart [zvpk](https://github.com/z-------------/zvpk).

```nim
import vpk
```

## **type** Vpk


```nim
Vpk = object
 header*: VpkHeader
 entries*: Table[string, VpkDirectoryEntry]
 signatureSection*: Option[VpkSignatureSection]
 filename*: string
```

## **type** VpkHeader


```nim
VpkHeader = object
 magicNumber*: uint32
 version*: uint32
 treeSize*: uint32
 fileDataSectionSize*: uint32
 archiveMd5SectionSize*: uint32
 otherMd5SectionSize*: uint32
 signatureSectionSize*: uint32
 endOffset*: int64
```

## **type** VpkDirectoryEntry


```nim
VpkDirectoryEntry = object
 crc*: uint32
 preloadBytes*: uint16
 archiveIndex*: uint16
 entryOffset*: uint32
 entryLength*: uint32
 endOffset*: int64
```

## **type** VpkSignatureSection


```nim
VpkSignatureSection = object
 publicKey*: string
 signature*: string
```

## **type** VpkCheckHashResult


```nim
VpkCheckHashResult = tuple[result: bool, message: string]
```

## **proc** fileDataOffset


```nim
func fileDataOffset(header: VpkHeader): uint32 {forbids: [].}
```

## **proc** totalLength


```nim
func totalLength(dirEntry: VpkDirectoryEntry): uint32 {forbids: [].}
```

## **proc** close

close dir file and any archive files

```nim
proc close(v: var Vpk) {forbids: [].}
```

## **proc** getArchiveFilename


```nim
func getArchiveFilename(v: Vpk; archiveIndex: uint32): string {.raises: [CatchableError], forbids: [].}
```

## **proc** readHeader


```nim
proc readHeader(f: File): VpkHeader {.raises: [IOError, CatchableError], tags: [ReadIOEffect], forbids: [].}
```

## **proc** readDirectoryEntry


```nim
proc readDirectoryEntry(f: File): VpkDirectoryEntry {.raises: [IOError, CatchableError], tags: [ReadIOEffect], forbids: [].}
```

## **proc** readDirectory


```nim
proc readDirectory(f: File): Table[string, VpkDirectoryEntry] {.raises: [IOError, EOFError, CatchableError], tags: [ReadIOEffect], forbids: [].}
```

## **proc** readFile


```nim
proc readFile(v: var Vpk; dirEntry: VpkDirectoryEntry; outBuf: pointer;
 outBufLen: uint32) {.raises: [IOError, CatchableError], tags: [ReadIOEffect], forbids: [].}
```

## **proc** checkHashes


```nim
proc checkHashes(v: var Vpk): VpkCheckHashResult {.raises: [CatchableError, IOError, KeyError], tags: [ReadIOEffect], forbids: [].}
```

## **proc** readVpk


```nim
proc readVpk(f: File; filename: string): Vpk {.raises: [IOError, CatchableError, EOFError], tags: [ReadIOEffect], forbids: [].}
```

## **proc** readVpk


```nim
proc readVpk(filename: string): Vpk {.raises: [IOError, CatchableError, EOFError], tags: [ReadIOEffect], forbids: [].}
```
