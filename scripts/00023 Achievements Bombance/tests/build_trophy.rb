# frozen_string_literal: true
# Reproducible 22x22 pixel silhouette approved in the V2 mockup (no external gems).
# Run only explicitly, with the destination PNG as argument.
require 'zlib'
require 'fileutils'
pixels = Array.new(22 * 22) { [0, 0, 0, 0] }
draw = lambda do |x, y, w, h, color|
  h.times { |dy| w.times { |dx| pixels[(y + dy) * 22 + x + dx] = color + [255] } }
end
dark, mid, light = [102, 65, 26], [211, 148, 37], [255, 218, 105]
[[4,1,14,2,dark], [5,3,12,7,mid], [6,3,3,6,light], [8,10,6,3,mid],
 [9,13,4,4,dark], [10,13,2,4,light], [5,18,12,3,dark], [6,17,10,2,mid],
 [6,19,10,1,light], [1,3,4,2,mid], [1,5,2,5,mid], [3,9,4,2,mid],
 [17,3,4,2,mid], [19,5,2,5,mid], [15,9,4,2,mid], [17,3,2,1,light],
 [1,3,3,1,light]].each { |args| draw.call(*args) }
chunk = ->(kind, data) { [data.bytesize].pack('N') + kind + data + [Zlib.crc32(kind + data)].pack('N') }
raw = pixels.each_slice(22).map { |row| "\0" + row.flatten.pack('C*') }.join
png = [137,80,78,71,13,10,26,10].pack('C*') + chunk.call('IHDR', [22,22,8,6,0,0,0].pack('NNC5')) +
      chunk.call('IDAT', Zlib::Deflate.deflate(raw)) + chunk.call('IEND', '')
path = ARGV.fetch(0)
FileUtils.mkdir_p(File.dirname(path))
File.binwrite(path, png)
puts "Trophy: #{path} (22x22 RGBA)"

