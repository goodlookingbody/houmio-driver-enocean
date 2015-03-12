async = require 'async'
Bacon = require 'baconjs'
carrier = require 'carrier'
enocean = require './enocean'
net = require 'net'
serialport = require 'serialport'
winston = require 'winston'
zerofill = require 'zerofill'

houmioBridge = process.env.HOUMIO_BRIDGE || "localhost:3001"
enoceanDeviceFile = process.env.HOUMIO_ENOCEAN_DEVICE_FILE || "/dev/ttyAMA0"
enoceanSerialConfig = { baudrate: 57600, parser: serialport.parsers.raw }
enoceanSerial = new serialport.SerialPort enoceanDeviceFile, enoceanSerialConfig, true
bridgeSocket = new net.Socket()

console.log "Using HOUMIO_BRIDGE=#{houmioBridge}"
console.log "Using HOUMIO_ENOCEAN_DEVICE_FILE=#{enoceanDeviceFile}"

exit = (msg) ->
  console.log msg
  process.exit 1

toSemicolonSeparatedHexString = (bytes) ->
  toHexString = (i) -> i.toString(16)
  addZeroes = (s) -> zerofill(s, 2)
  bytes.map(toHexString).map(addZeroes).join(':')

toEnoceanBuffers = (serial) ->
  Bacon.fromBinder (sink) ->
    serial.on "data", sink
    serial.on "close", -> sink new Bacon.End()
    serial.on "error", (err) -> sink new Bacon.Error(err)
    ( -> )

toEnoceanMessages = (buffers) ->
  buffers
    .filter enocean.bufferStartsWithStartByte
    .flatMap (buffer) -> buffers.startWith(buffer).bufferWithTime(100).take(1)
    .map Buffer.concat
    .filter enocean.bufferHasValidLength

toLines = (socket) ->
  Bacon.fromBinder (sink) ->
    carrier.carry socket, sink
    socket.on "close", -> sink new Bacon.End()
    socket.on "error", (err) -> sink new Bacon.Error(err)
    ( -> )

isWriteMessage = (message) -> message.command is "write"

openBridgeMessageStream = (socket) -> (cb) ->
  socket.connect houmioBridge.split(":")[1], houmioBridge.split(":")[0], ->
    lineStream = toLines socket
    messageStream = lineStream.map JSON.parse
    cb null, messageStream

openEnoceanMessageStream = (enoceanSerial) -> (cb) ->
  enoceanSerial.on 'open', ->
    messageStream = toEnoceanMessages toEnoceanBuffers enoceanSerial
    cb null, messageStream

bridgeMessagesToSerial = (bridgeStream, serial) ->
  bridgeStream
    .filter isWriteMessage
    .bufferingThrottle 25
    .onValue (message) ->
      serial.write message.data, ( -> )
      console.log "<-- Enocean:", toSemicolonSeparatedHexString(message.data)

toSocketMessage = (data) ->
  object = { command: "driverData", protocol: "enocean", data: data }
  string = JSON.stringify(object) + "\n"
  { object, string }

enoceanMessagesToSocket = (enoceanStream, socket) ->
  enoceanStream
    .map toSocketMessage
    .onValue (message) ->
      socket.write message.string
      console.log "--> Bridge: ", toSemicolonSeparatedHexString(message.object.data.toJSON())

openStreams = [ openEnoceanMessageStream(enoceanSerial), openBridgeMessageStream(bridgeSocket) ]

async.series openStreams, (err, [enoceanStream, bridgeStream]) ->
  if err then exit err
  bridgeStream.onEnd -> exit "Bridge stream ended"
  bridgeStream.onError (err) -> exit "Error from bridge stream:", err
  enoceanStream.onEnd -> exit "Enocean stream ended"
  enoceanStream.onError (err) -> exit "Error from Enocean stream:", err
  bridgeMessagesToSerial bridgeStream, enoceanSerial
  enoceanMessagesToSocket enoceanStream, bridgeSocket
  bridgeSocket.write (JSON.stringify { command: "driverReady", protocol: "enocean"}) + "\n"
  enoceanSerial.write enocean.getSubDefBaseIdCommand(), ( -> )
