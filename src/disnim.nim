import std/base64
import std/json
import std/net
import std/parseutils
import std/random
import std/strformat
import std/strutils
import std/tables
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

  let response = HttpResponse(
    code : code,
    headers : response_headers,
    body : body,
  )
  response

proc makeConnection(address : string, port : int) : (Socket,SslContext) =
  let socket = newSocket()
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
    response_headers = newTable[string, string]()
    line = ""
    body = ""
    content_length = 0
  
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

proc connect(gateway : string) : void =
  let
    port = 443
    path = "/"
  var
    header_map = newTable[string,string]()
    random_bytes: array[16, uint8]

  randomize(0)
  
  for i in 0 .. 15:
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
  echo response

when isMainModule:
  let gateway = getGateway()
  connect(gateway[6..gateway.len-1])