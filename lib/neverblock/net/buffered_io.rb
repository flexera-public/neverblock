# Monkeypatch Net::BufferedIO#rbuf_fill
# use NeverBlock to wait on IO, not IO.select

module Net
  class BufferedIO
    def rbuf_fill
      @rbuf << @io.read_nonblock(BUFSIZE)
    rescue IO::WaitReadable, Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::EINTR => e
      Timeout.timeout(@read_timeout, Net::ReadTimeout) do
        NB.wait(:read, @io)
      end
      retry # Can't have retry inside of the block due to 'Invalid retry (SyntaxError)'
    rescue IO::WaitWritable => e
      Timeout.timeout(@read_timeout, Net::ReadTimeout) do
        NB.wait(:write, @io)
      end
      retry # Can't have retry inside of the block due to 'Invalid retry (SyntaxError)'
    end
  end 
end
