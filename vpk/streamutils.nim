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

import std/macros
from std/sequtils import toSeq

template raiseNotEnoughData(expectedLen: int) =
  raise newException(CatchableError, "not enough data left to read " & $expectedLen & " bytes")

proc readBufferStrict(f: File; outBuf: pointer; outBufLen: SomeInteger) =
  if f.readBuffer(outBuf, outBufLen) != outBufLen.int:
    raiseNotEnoughData(outBufLen)

proc readBufferStrict*(f: File; outBuf: var openArray[char]) =
  if outBuf.len > 0:
    if f.readChars(outBuf) != outBuf.len:
      raiseNotEnoughData(outBuf.len)

proc read*(f: File; T: typedesc): T =
  f.readBufferStrict(result.addr, sizeof(T))

proc readString*(f: File): string =
  while true:
    let c = f.readChar()
    if c == '\0':
      break
    result.add(c)

iterator fields(t: NimNode): NimNode =
  for fieldNode in t.getType[1].getType[2]:
    yield fieldNode

macro readStruct*(f: File; T: typedesc): untyped =
  var stmtList = newStmtList()
  stmtList.add(nnkVarSection.newTree(
    nnkIdentDefs.newTree(
      newIdentNode("obj"),
      T,
      newEmptyNode()
    )
  ))
  for fieldNode in T.fields:
    stmtList.add(nnkAsgn.newTree(
      nnkDotExpr.newTree(
        newIdentNode("obj"),
        fieldNode
      ),
      nnkCall.newTree(
        nnkDotExpr.newTree(
          f,
          newIdentNode("read")
        ),
        nnkCall.newTree(
          newIdentNode("type"),
          nnkDotExpr.newTree(
            newIdentNode("obj"),
            fieldNode
          )
        )
      )
    ))
  stmtList.add(newIdentNode("obj"))
  result = newBlockStmt(stmtList)

func buildSizeofTree(T: NimNode; fieldNodes: seq[NimNode]): NimNode =
  if fieldNodes.len == 0:
    newLit(0)
  else:
    let rest = fieldNodes[1 .. ^1]
    infix(newCall(bindSym"sizeof", newDotExpr(T, fieldNodes[0])), "+", buildSizeofTree(T, rest))

macro sizeOfStruct*(T: typedesc): untyped =
  result = nnkPar.newTree(
    buildSizeofTree(T, toSeq(T.fields))
  )
