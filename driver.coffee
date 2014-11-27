Bacon = require('baconjs')
serialport = require("serialport")
sleep = require('sleep')
WebSocket = require('ws')
winston = require('winston')

winston.remove(winston.transports.Console)
winston.add(winston.transports.Console, { timestamp: ( -> new Date() ) })
console.log = winston.info

houmioBridge = process.env.HOUMIO_BRIDGE || "ws://localhost:3001"
enOceanDeviceFile = process.env.HOUMIO_ENOCEAN_DEVICE_FILE || "/dev/cu.usbserial-FTXMJM92"

console.log "Using HOUMIO_BRIDGE=#{houmioBridge}"
console.log "Using HOUMIO_ENOCEAN_DEVICE_FILE=#{enOceanDeviceFile}"

exit = (msg) ->
  console.log msg
  process.exit 1

enOceanSerialBuffer = null
onEnOceanTimeoutObj = null
socket = null
pingId = null

enOceanData = new Bacon.Bus()
writeReady = new Bacon.Bus()

enOceanWriteAndDrain = (data, callback) ->
  enOceanSerial.write data, (err, res) ->
    enOceanSerial.drain callback

enOceanData
  .zip(writeReady, (d, w) -> d)
  .flatMap (d) -> Bacon.fromNodeCallback(enOceanWriteAndDrain, d)
  .onValue (err) ->
    sleep.usleep(0.01*1000000)
    writeReady.push(true)

enOceanStartByte = 0x55

enOceanHeaderLength = 6

onEnOceanTimeout = () ->
  enOceanSerialBuffer = null
  clearTimeout onEnOceanTimeoutObj

enOceanIsDataValid = (cmd) ->
  if cmd.length < 7 then return false
  if cmd[0] != enOceanStartByte then return false
  if !enOceanIsDataLengthValid(cmd) then return false
  true

enOceanIsDataLengthValid = (data) ->
  dataLen = data[1] * 0xff + data[2]
  optLen = data[3]
  totalLen = enOceanHeaderLength + dataLen + optLen + 1
  data.length == totalLen

onSocketOpen = ->
  console.log "Connected to #{houmioBridge}"
  pingId = setInterval ( -> socket.ping(null, {}, false) ), 3000
  publish = JSON.stringify { command: "driverReady", data: { protocol: "enocean" } }
  socket.send(publish)
  console.log "Sent message:", publish

onSocketClose = ->
  clearInterval pingId
  exit "Disconnected from #{houmioBridge}"

onSocketMessage = (s) ->
  console.log "Received message:", s
  try
    message = JSON.parse s
    enOceanData.push message.data

onEnOceanSerialData = (data) ->
  if data[0] == enOceanStartByte && enOceanSerialBuffer == null
    onEnOceanTimeoutObj = setTimeout onEnOceanTimeout, 100
    if enOceanIsDataValid data
      socket.send JSON.stringify { command: "enoceandata", data: data }
      enOceanSerialBuffer = null
      clearTimeout onEnOceanTimeoutObj
    else
      enOceanSerialBuffer = data.slice 0, data.length
  else if enOceanSerialBuffer != null
    enOceanSerialBuffer = Buffer.concat [enOceanSerialBuffer, data]
    if enOceanIsDataValid enOceanSerialBuffer
      datamessage = JSON.stringify { command: "enoceandata", data: enOceanSerialBuffer }
      socket.send datamessage
      console.log "Sent message:", datamessage
      enOceanSerialBuffer = null
      clearTimeout onEnOceanTimeoutObj

onEnOceanSerialOpen = ->
  console.log 'Serial port opened:', enOceanDeviceFile
  enOceanSerial.on 'data', onEnOceanSerialData
  writeReady.push(true)
  socket = new WebSocket(houmioBridge)
  socket.on 'open', onSocketOpen
  socket.on 'close', onSocketClose
  socket.on 'error', exit
  socket.on 'ping', -> socket.pong()
  socket.on 'message', onSocketMessage

onEnOceanSerialError = (err) ->
  exit "An error occurred in EnOcean serial port: #{err}"

onEnOceanSerialClose = (err) ->
  exit "EnOcean serial port closed, reason: #{err}"

enOceanSerialConfig = { baudrate: 57600, parser: serialport.parsers.raw }
enOceanSerial = new serialport.SerialPort enOceanDeviceFile, enOceanSerialConfig, true
enOceanSerial.on "open", onEnOceanSerialOpen
enOceanSerial.on "close", onEnOceanSerialClose
enOceanSerial.on "error", onEnOceanSerialError
