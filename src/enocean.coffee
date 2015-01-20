crc = require("crc")

SYNC = 0x55

PT_COMMON_COMMAND = 0x05

CO_RD_ID_BASE = 0x08

crcOf = (ints) -> parseInt crc.crc8(ints), 16

enoceanBytes = (header, data) -> [SYNC].concat(header).concat(crcOf(header)).concat(data).concat(crcOf(data))

getSubDefBaseIdCommand = ->
  header = [0x00, 0x01, 0x00, PT_COMMON_COMMAND]
  data = [CO_RD_ID_BASE]
  enoceanBytes header, data

bufferDataLength = (buffer) ->
  buffer[1] * 0xff + buffer[2]

bufferOptionalDataLength = (buffer) ->
  buffer[3]

bufferStartsWithStartByte = (buffer) ->
  buffer[0] == 0x55

bufferHasValidLength = (buffer) ->
  enoceanHeaderLength = 6
  totalLength = enoceanHeaderLength + (bufferDataLength buffer) + (bufferOptionalDataLength buffer) + 1
  buffer.length == totalLength

exports.bufferStartsWithStartByte = bufferStartsWithStartByte
exports.bufferHasValidLength = bufferHasValidLength
exports.getSubDefBaseIdCommand = getSubDefBaseIdCommand
