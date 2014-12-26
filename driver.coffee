Bacon = require('baconjs')
carrier = require('carrier')
net = require('net')
serialport = require("serialport")
sleep = require('sleep')
winston = require('winston')
zerofill = require('zerofill')

winston.remove(winston.transports.Console)
winston.add(winston.transports.Console, { timestamp: ( -> new Date() ) })
console.log = winston.info

houmioBridge = process.env.HOUMIO_BRIDGE || "localhost:3001"
enOceanDeviceFile = process.env.HOUMIO_ENOCEAN_DEVICE_FILE || "/dev/ttyAMA0"

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
  socket.write (JSON.stringify { command: "driverReady", protocol: "enocean"}) + "\n"
  carrier.carry socket, onSocketData
  socket.on 'close', onSocketClose
  socket.on 'error', (err) -> console.log err

onSocketClose = ->
  exit "Disconnected from #{houmioBridge}"

onSocketData = (line) ->
  try
    message = JSON.parse line
    enOceanData.push message.data
    console.log "Wrote to serial port:", toCommaSeparatedHexString message.data

toCommaSeparatedHexString = (ints) ->
  toHexString = (i) -> i.toString(16)
  addZeroes = (s) -> zerofill(s, 2)
  ints.map(toHexString).map(addZeroes).join(':')

sendData = (d) ->
  o = { command: "driverData", protocol: "enocean", data: d }
  s = JSON.stringify o
  socket.write s + "\n"
  console.log "Sent driver data:", toCommaSeparatedHexString(JSON.parse(s).data)

onEnOceanSerialData = (data) ->
  if data[0] == enOceanStartByte && enOceanSerialBuffer == null
    onEnOceanTimeoutObj = setTimeout onEnOceanTimeout, 100
    if enOceanIsDataValid data
      sendData data
      enOceanSerialBuffer = null
      clearTimeout onEnOceanTimeoutObj
    else
      enOceanSerialBuffer = data.slice 0, data.length
  else if enOceanSerialBuffer != null
    enOceanSerialBuffer = Buffer.concat [enOceanSerialBuffer, data]
    if enOceanIsDataValid enOceanSerialBuffer
      sendData enOceanSerialBuffer
      enOceanSerialBuffer = null
      clearTimeout onEnOceanTimeoutObj

onEnOceanSerialOpen = ->
  console.log 'Serial port opened:', enOceanDeviceFile
  enOceanSerial.on 'data', onEnOceanSerialData
  writeReady.push(true)
  socket = new net.Socket()
  socket.connect houmioBridge.split(":")[1], houmioBridge.split(":")[0], onSocketOpen

onEnOceanSerialError = (err) ->
  exit "An error occurred in EnOcean serial port: #{err}"

onEnOceanSerialClose = (err) ->
  exit "EnOcean serial port closed, reason: #{err}"

enOceanSerialConfig = { baudrate: 57600, parser: serialport.parsers.raw }
enOceanSerial = new serialport.SerialPort enOceanDeviceFile, enOceanSerialConfig, true
enOceanSerial.on "open", onEnOceanSerialOpen
enOceanSerial.on "close", onEnOceanSerialClose
enOceanSerial.on "error", onEnOceanSerialError
