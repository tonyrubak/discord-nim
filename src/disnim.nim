import std/base64
import std/json
import std/nativesockets
import std/net
import std/parseutils
import std/random
import std/sequtils
import std/strformat
import std/strutils
import std/tables
import std/unittest

import websockets
# This is just an example to get you started. A typical binary package
# uses this file as the main entry point of the application.

type
  HttpRequest = object
    httpMethod, uri, body: string
    headers: TableRef[string, string]

type
  HttpResponse = object
    code: uint
    headers: TableRef[string, string]
    body: string

proc writeRequest(sock : Socket, request : HttpRequest) : void =
  sock.send(&"{request.httpMethod} {request.uri} HTTP/1.1\r\n")
  for k, v in request.headers:
    sock.send(&"{k}: {v}\r\n")
  sock.send("\r\n")
  if request.body.len > 0:
    sock.send(&"{request.body}\r\n")

proc readResponse(socket : Socket) : HttpResponse =
  var
    line = ""
    response_headers = newTable[string, string]()
    content_length = 0
    body = ""
  # Read Status Line
  socket.readLine(line)
  let code = line.captureBetween(' ',' ').parseUInt

  socket.readLine(line) # Read first header line
  while line != "\r\n":
    var
      key = ""
      value = ""
    let endOfKey = parseUntil(line, key, ':')
    key = key.toLowerAscii
    value = line[endOfKey+2 .. line.len-1]
    response_headers[key] = value
    socket.readLine(line)
  
  if response_headers.hasKey("content-length"):
    content_length = response_headers["content-length"].parseInt
    body = socket.recv(content_length)
  else:
    var temp = ""
    var bytes_read = socket.recv(temp, 4096)
    while bytes_read == 4096:
      body = body & temp
      bytes_read = socket.recv(temp, 4096)
    body = body & temp

  let response = HttpResponse(
    code : code,
    headers : response_headers,
    body : body,
  )
  echo response.body
  response

proc makeConnection(address : string, port : int) : (Socket,SslContext) =
  let socket = newSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP, buffered = false)
  let ctx = newContext()
  wrapSocket(ctx, socket)
  socket.connect(address, Port(port))
  return (socket,ctx)

proc getGateway(): string =
  let 
    address = "discord.com"
    port = 443
    path = "/api/gateway"
  var
    header_map = newTable[string, string]()
  
  header_map["Host"] = address
  header_map["User-Agent"] = "TestBot (www.test.bot, 0.1)"

  let request = HttpRequest(
      httpMethod : "GET",
      uri : path,
      body : "",
      headers : header_map)

  let
    (socket,ctx) = makeConnection(address,port)
  socket.writeRequest(request)
  let response = socket.readResponse()
  response.body.parseJson["url"].getStr

proc connect(gateway : string) : bool =
  let
    port = 443
    path = "/"
  var
    header_map = newTable[string,string]()
    random_bytes: array[16, uint8]

  randomize(0)
  
  for i in 0 .. random_bytes.len-1:
    random_bytes[i] = uint8.rand
  let encoded_bytes = random_bytes.encode

  header_map["Host"] = gateway
  header_map["User-Agent"] = "TestBot (www.test.bot, 0.1)"
  header_map["Upgrade"] = "websocket"
  header_map["Sec-WebSocket-Key"] = encoded_bytes
  header_map["Sec-WebSocket-Version"] = "13"

  let request = HttpRequest(
    httpMethod : "GET",
    uri : path,
    body : "",
    headers : header_map,
  )

  var (sock,ctx) = makeConnection(gateway, port)
  sock.writeRequest(request)
  let response = sock.readResponse

  # RFC 6455 compliance stuff that we probably don't need
  # but we should check anyways

  # First check to see if we got a 101 response.
  # We don't handle any other kind of responses.

  # If the status code received from the server is not 101, the
  # client handles the response per HTTP [RFC2616] procedures.  In
  # particular, the client might perform authentication if it
  # receives a 401 status code; the server might redirect the client
  # using a 3xx status code (but clients are not required to follow
  # them), etc.  Otherwise, proceed as follows.
  if response.code != 101:
    echo "Not code 101"
    return false

  # If the response lacks an |Upgrade| header field or the |Upgrade|
  # header field contains a value that is not an ASCII case-
  # insensitive match for the value "websocket", the client MUST
  # _Fail the WebSocket Connection_.
  if (not response.headers.hasKey("connection")) or response.headers["connection"] != "upgrade":
      echo "No connection or connection not upgrade"
      return false

  # If the response lacks a |Connection| header field or the
  # |Connection| header field doesn't contain a token that is an
  # ASCII case-insensitive match for the value "Upgrade", the client
  # MUST _Fail the WebSocket Connection_.
  if (not response.headers.hasKey("upgrade")) or response.headers["upgrade"] != "websocket":
      echo "No upgrade or upgrade not websocket"
      return false

  # @TODO Need to check to ensure that Sec-WebSocket-Accept header field
  # is SHA-1 concatenation of the encoded bytes we sent with the string
  # 258EAFA5-E914-47DA-95CA-C5AB0DC85B11

  # If the response lacks a |Sec-WebSocket-Accept| header field or
  # the |Sec-WebSocket-Accept| contains a value other than the
  # base64-encoded SHA-1 of the concatenation of the |Sec-WebSocket-
  # Key| (as a string, not base64-decoded) with the string "258EAFA5-
  # E914-47DA-95CA-C5AB0DC85B11" but ignoring any leading and
  # trailing whitespace, the client MUST _Fail the WebSocket
  # Connection_.
  if not response.headers.hasKey("sec-websocket-accept"):
    echo "No Sec-WebSocket-Accept"
    return false
    
  return true

when isMainModule:
  let gateway = getGateway()
  if connect(gateway[6..<gateway.len]):
    echo "Connection successful"
  else:
    echo "Connection unsuccessful"