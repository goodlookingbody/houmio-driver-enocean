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
