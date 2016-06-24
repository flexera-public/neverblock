# Author::    Mohammad A. Ali  (mailto:oldmoe@gmail.com)
# Copyright:: Copyright (c) 2009 eSpace, Inc.
# License::   Distributes under the same terms as Ruby

require 'socket'
require 'fcntl'

require_relative 'io'

class BasicSocket < IO

  @@getaddress_method = IPSocket.method(:getaddress)
  def self.getaddress(*args)
    @@getaddress_method.call(*args)
  end

  alias_method :recv_blocking, :recv

  def recv_neverblock(*args)
    res = ""
    begin
      old_flags = self.fcntl(Fcntl::F_GETFL, 0)
      res << recv_nonblock(*args)
      self.fcntl(Fcntl::F_SETFL, old_flags)
    rescue Errno::EWOULDBLOCK, Errno::EAGAIN, Errno::EINTR
      self.fcntl(Fcntl::F_SETFL, old_flags)
      NB.wait(:read, self)
      retry
    end
    res
  end

  def recv(*args)
    if NB.neverblocking?
      recv_neverblock(*args)
    else
      recv_blocking(*args)
    end
  end

end


# Commenting out connect neverblocking.  This can cause SSL errors
class Socket < BasicSocket
  
  alias_method :connect_blocking, :connect
  
  def connect_neverblock(server_sockaddr)
    begin
      connect_nonblock(server_sockaddr)
    rescue Errno::EINPROGRESS, Errno::EINTR, Errno::EALREADY, Errno::EWOULDBLOCK
      NB.wait(:write, self)
      retry
    rescue Errno::EISCONN
      # do nothing, we are good
    end
  end
    
  def connect(server_sockaddr)
    NB.logger.error "DJR DJR Socket connect START" rescue nil
#     if NB.neverblocking?
#       connect_neverblock(server_sockaddr)
#     else
    connect_blocking(server_sockaddr)
    NB.logger.error "DJR DJR Socket connect END" rescue nil
#     end
  end

end

Object.send(:remove_const, :TCPSocket)

class TCPSocket < Socket
  def initialize(*args)
    super(AF_INET, SOCK_STREAM, 0)
    # method 'sockaddr_in' reqiures only two params so that
    # we have to make sure that we don't pass more than two.
    # http://www.ruby-doc.org/stdlib-1.9.3/libdoc/socket/rdoc/Socket.html#method-c-sockaddr_in
    self.connect(Socket.sockaddr_in(*(args[0..1].reverse)))
  rescue Exception => e
    # NB redefines TCPSocket out of some reason. TCPSocket normally inherits from IPSocket which handles
    # connection failures and closes any open fd. Since NB is redefining TCPSocket and is not inheriting
    # from IPSocket, we have to clean up of open fds when catching an exception.
    begin
      self.close
    rescue Exception
    ensure
      raise e
    end
  end
end

