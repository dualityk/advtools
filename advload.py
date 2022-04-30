#!/usr/bin/python

# Host component to Advantage serial boot loader.  And a bunch of other shit.

# Where is the serial port?
SERIAL = "/dev/ttyUSB0"

# Where does stage 2 of the boot loader start?
LOADER = "serialboot.bin"
STAGE2 = 0x29



import serial, struct, time 
from functools import reduce

adv = serial.Serial(SERIAL, 19200, timeout=2, xonxoff=False, rtscts=False) 

# Send stage 2 loader.  If we get anything back, it worked.
def sendloader(connection):
    connection.reset_input_buffer()
    connection.reset_output_buffer()
    l=open(LOADER,'r')
    l.seek(STAGE2)
    loader=l.read()
    print("loader bytes", len(loader), "so FF17 should be", hex(len(loader)))
    connection.write(loader)
    if connection.read(1) and sendstream(connection,0,'\x00'*10360+'\x42\xa5\x00\x00\x7e'+'\x00'*10115):
      return True
    else: return False
    
# Retrieve a block of data of any size, with error checking.
def getblock(connection, origin, size):
  data = ''
  while size:
    if size > 255: 
      request = 0
    else:
      request = size
    maxtries = 4
    goodnews = False
    advopinion = rawchk(connection, origin, request)
    while maxtries:
      maxtries -= 1
      attempt = rawread(connection, origin, request)
      if advopinion == checksum256(attempt):
      #if True:
        data += attempt
        origin += len(attempt)
        size -= len(attempt)
        goodnews = True        
        maxtries = 0
    if not goodnews: return False
  return data

# Send stream of any size, no error checking (right now).
def sendstream(connection, origin, data):
  return rawcwrite(connection, origin, tomagic(data))
  
# Send a block of data of any size, with error checking.
def sendblock(connection, origin, data):
  spot = 0
  working = True
  while spot < len(data):
    if len(data)-spot < 256:
      endspot = len(data)
    else:
      endspot = spot + 256
    request = data[spot:endspot]
    maxtries = 4
    goodnews = False
    while maxtries:
      maxtries -= 1      
      if rawwrite(connection, origin, request) \
      and rawchk(connection, origin, len(request)) == checksum256(request):
        spot = endspot
        origin += len(request)
        goodnews = True
        maxtries = 0
    if not goodnews: return False
  return True  
    

# XXX These are the raw routines: 1:1 bootloader commands.

# Read a block of data.
def rawread(connection, origin, size):
    connection.write(cmdstring(origin, size, 1))
    if size == 0: size = 256
    j=connection.read(size)
    k=connection.read(1)
    if k == 'k': return j
    else: 
      print("error at origin",origin)
      return [j,k]
  
# Get checksum for data.
def rawchk(connection, origin, size):
    if size == 256: size = 0
    connection.write(cmdstring(origin, size, 2))
    j=connection.read(1)
    if len(j): return ord(j)
    else: return False
     
# Write a block of data.
def rawwrite(connection, origin, block):
    if len(block) == 256:
      askfor = 0 
    else: 
      askfor = len(block)
    connection.write(cmdstring(origin, askfor, 0))
    connection.write(block)
    if connection.read(1) == 'r': return True
    else: return False

# Null a memory block.
def rawnull(connection, origin, size):
    connection.write(cmdstring(origin, size, 3))
    if connection.read(1) == 'n': return True
    else: return False
    
# Boot!  Jump to some location and away you go.
def boot(connection, origin):
    connection.write(cmdstring(origin, 0, 4))
    return connection.read(1)
    
# Compressed data send.
def rawcwrite(connection, origin, data):
    connection.write(cmdstring(origin, 0, 5))
    connection.write(data)
    if connection.read(1) == 'c': return True
    else: return False

# Port read
def ioread(connection, port):
    connection.write(cmdstring(port, 0, 6))
    k=connection.read(1)
    if len(k): return k
    else: return False

# Port write
def iowrite(connection, port, data):
    connection.write(cmdstring(port, data, 7))
    k=connection.read(1)
    if len(k): return k
    else: return False

# XXX These are the little helper routines.

# Combine tracks and write disk image to disk.
def writensi(image, file):
  f=open(file,'w')
  for i in range(70):
    f.write(image[i])
  f.close()

# Read nsi image from disk and split into tracks.
def readnsi(file):
  image=[b'']*70
  f=open(file,'r')
  for i in range(70):
    image[i]=f.read(5120)
  return image

# Prepare a command string.
def cmdstring(address, size, cmd):
    return struct.pack('<HBB', address, size, cmd)
    
# Find a checksum (shamelessly stolen)
def checksum256(st):
    return reduce(lambda x,y:x+y, list(map(ord, st))) % 256

# Encode magic RLE.
def tomagic(string):
  output = b''
  packet = b''
  stremain = len(string)
  pos = 0
  cpexts = 0
  unexts = 0
  pkts = 0
  while stremain:
    # If there's not enough space for at least one data and one filler byte,
    # pad out and write.
    if len(packet) == 256:
      output += packet
      packet = b''
      pkts += 1
    elif len(packet) == 255:
      output += packet + '\x00'
      packet = b''
      pkts += 1
      
    # Compressed case.    
    count = 0
    if stremain > 1 and string[pos] == string[pos+1]:
      cpexts += 1
      char = string[pos]
      while pos < len(string) and count < 128 and string[pos] == char:
        count += 1
        pos += 1
      packet += chr(count+127)+char
    else:
    # Uncompressed case.      
      unexts += 1
      raw = b''
      maxct = min(127, 255-len(packet))
      while pos < len(string) and count < maxct:
        # If there is a next character, see if it's time to compress.
        if pos+1 < len(string) and string[pos] == string[pos+1]:
          break
        count += 1
        raw += string[pos]
        pos += 1
      packet += chr(count)+raw
    stremain = len(string)-pos
  # End of stream.  
  output += packet + chr(0x80)
  print("source", len(string), "result", len(output), "packets", pkts, "compressed runs", cpexts, "uncompressed runs", unexts)
  return output
    
# Decode magic RLE
def frommagic(string):
  output = b''
  pos = 0
  while pos < len(string):
    count = ord(string[pos]) & 0x7f
    cflag = ord(string[pos]) & 0x80
    pos += 1 
    # Regular case: count is nonzero
    if count:
      if cflag:
        # Run length
        output += string[pos]*(count+1)
        pos += 1
      else:
        # Raw data        
        output += string[pos:pos+count]
        pos += count
    else:
    # Special case: control characters
      if cflag:
        # End of stream
        return output
  return output, False
        
# Is this thing on?
def youawake(connection):        
  connection.reset_input_buffer()
  connection.write('    ')
  if connection.read() == '?': return True 
  else: return False


def sl(): return sendloader(adv)

# XXX These are the actual applications, which take care of sending the
# loader and so forth.

# Disk read application, returns disk image if successful.  (x = diskread(adv))
def diskread(connection): 
  print("Send stage 2 loader")
  if not sendloader(connection): return False
  print("Send pretty picture")
  if not sendstream(connection,0,open('fread.advpic').read()): return False
  print("Send disk read component")
  if not sendblock(connection,0xe000,open('fread.bin').read()): return False
  print("Boot")
  boot(connection,0xe000)
  print("Wait for serial data, ctrl-c to interrupt")
  tracks = [b'']*70
  try:
    for i in range(35):
      while len(tracks[i]) < 5120:
        tracks[i]+=connection.read()
      print("Received side 0 track",i)
      j = 69-i		# side 1 tracks are reverse order
      while len(tracks[j]) < 5120:
        tracks[j]+=connection.read()
      print("Received side 1 track",j)
    print("Got it.")
    if connection.read()=='\xab':
      print("Read complete, returned to stage 1")
  except KeyboardInterrupt:
    print("Interrupted, returning what was read so far")
    return [tracks, False]
  return tracks

# Read only the metadata (sector ID and CRC) from the disk.  For debug only.
def disksectorids(connection): 
  print("Send stage 2 loader")
  if not sendloader(connection): return False
  print("Send pretty picture")
  if not sendstream(connection,0,open('fread.advpic').read()): return False
  print("Send disk read component")
  if not sendblock(connection,0xe000,open('fsecid.bin').read()): return False
  print("Boot")
  boot(connection,0xe000)
  print("Wait for serial data, ctrl-c to interrupt")
  tracks = [b'']*70
  try:
    for i in range(35):
      while len(tracks[i]) < 20:
        tracks[i]+=connection.read()
      print("Received side 0 track",i)
      j = 69-i		# side 1 tracks are reverse order
      while len(tracks[j]) < 20:
        tracks[j]+=connection.read()
      print("Received side 1 track",j)
    print("Got it.")
    if connection.read()=='\xab':
      print("Read complete, returned to stage 1")
  except KeyboardInterrupt:
    print("Interrupted, returning what was read so far")
    return [tracks, False]
  return tracks

# Not implemented yet.
def fddlib(connection):
  print("Send stage 2 loader")
  if not sendloader(connection): return False
  print("Send fdd library")
  if not sendblock(connection,0xe000,open('lib/fdd.bin').read()): return False
  print("Boot")
  return boot(connection,0xe000)

  
# Disk write utility.
def diskwrite(connection, image):
  disk=readnsi(image)
  print("Send second stage loader")
  if not sendloader(connection): return False
  print("Send pretty picture")
  if not sendstream(connection,0,open('fwrite.advpic').read()): return False
  print("Send disk writer component")
  if not sendblock(connection,0xe000,open('fwrite.bin').read()): return False
  print("Boot")
  if not boot(connection,0xe000): return False
  print("Send image")
  return rawsendimage(connection, disk)

# Send diskimage to writer on Advantage.
def rawsendimage(connection, image):
  Running = True
  while Running:
    tracks=b''
    query=b''
    while not len(query):
      query=connection.read()
    query=ord(query)
    if query == 0xab:
      print("Done")
      return True
    elif query >= 0xf0:
      print("Error")
      return chr(query)+adv.read(3)
    else:
      print("Sending requested cylinders from", query)
      for i in range(5):
        tracks += image[query+i] + image[69-query-i]
      connection.write(tomagic(tracks))
        