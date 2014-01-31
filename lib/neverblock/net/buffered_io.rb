# Monkeypatch Net::BufferedIO#rbuf_fill
# use NeverBlock to wait on IO, not IO.select

module Net
  class BufferedIO
    def rbuf_fill
      @rbuf << @io.read_nonblock(BUFSIZE)
    rescue IO::WaitReadable, Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::EINTR => e
      NB.timeout_for_rbuf_fill(@read_timeout) do
        NB.wait(:read, @io)
      end
      retry # Can't have retry inside of the block due to 'Invalid retry (SyntaxError)'
    rescue IO::WaitWritable => e
      NB.timeout_for_rbuf_fill(@read_timeout) do
        NB.wait(:write, @io)
      end
      retry # Can't have retry inside of the block due to 'Invalid retry (SyntaxError)'
    end
  end 
end
