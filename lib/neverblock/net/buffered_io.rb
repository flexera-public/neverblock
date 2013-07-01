# Monkeypatch Net::BufferedIO#rbuf_fill
# use NeverBlock to wait on IO, not IO.select

module Net
  class BufferedIO
    def rbuf_fill
      @rbuf << @io.read_nonblock(BUFSIZE)
    rescue IO::WaitReadable, Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::EINTR => e
      Timeout.set_nb_timeout(@read_timeout) do
        NB.wait(:read, @io)
      end
      retry # Can't have retry inside of the block due to 'Invalid retry (SyntaxError)'
    rescue IO::WaitWritable => e
      Timeout.set_nb_timeout(@read_timeout) do
        NB.wait(:write, @io)
      end
      retry # Can't have retry inside of the block due to 'Invalid retry (SyntaxError)'
    end
  end 
end

require 'net/http'
module Net
  class HTTP
    alias_method :rb_connect, :connect

    def connect(*args)
      return rb_connect(*args) unless NB.neverblocking?

      NB.track_timeout_caller(:net_http_connect) do
        rb_connect(*args)
      end
    end
  end
end