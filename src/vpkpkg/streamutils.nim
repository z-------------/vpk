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

template `+@`*[T: SomeInteger](p: pointer; offset: T): pointer =
  ## Pointer offset
  cast[pointer](cast[ByteAddress](p) + offset.int64)

template readBufferStrict*[T: SomeInteger](f: File; outBuf: pointer; outBufLen: T) =
  if f.readBuffer(outBuf, outBufLen) != outBufLen.int:
    raise newException(CatchableError, "not enough data left to read " & $outBufLen & " bytes")

proc read*(f: File; T: typedesc): T =
  f.readBufferStrict(result.addr, sizeof(T))

proc readString*(f: File): string =
  while true:
    let c = f.readChar()
    if c == '\0':
      break
    result.add(c)
