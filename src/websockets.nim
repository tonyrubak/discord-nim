import std/nativesockets
import std/random
import std/sequtils
import std/strformat
import std/unittest

type
  WebSocketFrame* = object
    fin, opcode, mask: uint8
    payload_length: uint64
    payload: string

proc decode*(frame: seq[uint8]) : WebSocketFrame =
  let mask = frame[1].shr(7) and 1
  var
    len : uint64 = frame[1].uint8 and 0x7F
    len_bytes : uint8 = 0
    offset : uint64 = 2
    payload : seq[uint8]

  if (len == 126):
    offset = 4
    len_bytes = 2
    var
      nlen : uint16 = 0
      len_ptr = cast[ptr uint8](unsafeAddr(frame[2]))
    copyMem(nlen.addr, len_ptr, 2)
    len = ntohs(nlen)

  payload.setLen(len)
  if (mask == 0):
    for i in 0..len-1:
      payload[i] = frame[i+offset]
  else:
    offset += 4
    let mask_offset = len_bytes + 2
    for i in 0..len-1:
      payload[i] = frame[i+offset] xor frame[mask_offset + (i mod 4)]

  WebSocketFrame(
    fin : frame[0].shr(7) and 1,
    opcode : frame[0] and 0xF,
    mask : mask,
    payload_length : len,
    payload : cast[string](payload)
  )


when isMainModule:
  var frame = @[0x81.uint8,0x02.uint8,0xFF.uint8,0xEE.uint8]
  #  0    1   2    3    4567    8    9ABCDEF     
  # FIN RSV1 RSV2 RSV3 OPCODE MASK PAYLOAD_LENGTH
  #  1    0   0    0    1000 = 10000001 = 0x81
  #    0x02     = 00000010  =   0    0000010

  var parsedFrame = decode(frame);

  check(parsedFrame.fin == 1)
  check(parsedFrame.opcode == 1)
  check(parsedFrame.mask == 0)
  check(parsedFrame.payload_length == 2)
  check(frame[2..3] == cast[seq[uint8]](parsedFrame.payload.toSeq))

  #############################################################################
  var r = initRand(0)

  let
    length = rand(uint16)
    nlength = htons(length)
  
  frame.setLen(4+length)

  var
    len_ptr = cast[ptr uint8](unsafeAddr(frame[2]))
    payload_ptr = cast[ptr uint8](unsafeAddr(frame[4]))
    random_bytes : array[65535, uint8]

  for i in 0..(length-1).uint32:
    random_bytes[i] = rand(uint8)
  #  0    1   2    3    4567    8    9ABCDEF     
  # FIN RSV1 RSV2 RSV3 OPCODE MASK PAYLOAD_LENGTH
  #  1    0   0    0    1000 = 10000001 = 0x81
  frame[0] = 0x81;
  frame[1] = 0x7e;
  copyMem(len_ptr, nlength.unsafeAddr, 2)
  copyMem(payload_ptr, cast[ptr uint8](random_bytes.unsafeAddr), length)

  parsedFrame = decode(frame)

  
  check(parsedFrame.fin == 1)
  check(parsedFrame.opcode == 1)
  check(parsedFrame.mask == 0)
  check(parsedFrame.payload_length == length)
  check(cast[seq[uint8]](parsedFrame.payload.toSeq) == random_bytes[0..<length])

  # test "parses a simple masked websocket frame"
  # mask = 0x12345678;
  #  0    1   2    3    4567    8    9ABCDEF     
  # FIN RSV1 RSV2 RSV3 OPCODE MASK PAYLOAD_LENGTH
  #  1    0   0    0    1000 = 10000001 = 0x81
  #     0x02     = 00000010  =   1    0000010
  frame.setLen(8)
  frame[0] = 0x81
  frame[1] = 0x82
  frame[2] = 0x12
  frame[3] = 0x34
  frame[4] = 0x56
  frame[5] = 0x78
  frame[6] = (0xAA xor 0x12)
  frame[7] = (0xFF xor 0x34)

  parsedFrame = decode(frame);

  check(parsedFrame.fin == 1)
  check(parsedFrame.opcode == 1)
  check(parsedFrame.mask == 1)
  check(parsedFrame.payload_length == 2)
  check(cast[seq[uint8]](parsedFrame.payload.toSeq) == @[0xAA.uint8,0xFF.uint8])