require 'fcntl'
require 'openssl'

# This is an extention to the Ruby IO class that makes it compatable with
#  NeverBlocks event loop to avoid blocking IO calls. That's done by delegating
# Author::    Mohammad A. Ali  (mailto:oldmoe@gmail.com)
# Copyright:: Copyright (c) 2009 eSpace, Inc.
# License::   Distributes under the same terms as Ruby

class OpenSSL::SSL::SSLSocket
  def connect
    connect_nonblock
  rescue IO::WaitReadable
    NB.wait(:read, self)
    retry
  rescue IO::WaitWritable
    NB.wait(:write, self)
    retry
  end
end

class IO
  NB_BUFFER_LENGTH = 128 * 1024

  alias rb_sysread sysread
  alias rb_syswrite syswrite
  alias rb_read read
  alias rb_write write
  alias rb_gets gets
  alias rb_getc getc
  alias rb_readchar readchar
  alias rb_readline readline
  alias rb_readlines readlines
  alias rb_print print

  #  This method is the delegation method which reads using read_nonblock()
  #  and registers the IO call with event loop if the call blocks. The value
  # @immediate_result is used to get the value that method got before it was blocked.

  def read_neverblock(*args)
    res = ''
    begin
      old_flags = get_flags
      res << read_nonblock(*args)
      set_flags(old_flags)
    rescue Errno::EWOULDBLOCK, Errno::EAGAIN, Errno::EINTR
      set_flags(old_flags)
      NB.wait(:read, self)
      retry
    end
    res
  end

  #  The is the main reading method that all other methods use.
  #  If the mode is set to neverblock it uses the delegation method.
  #  Otherwise it uses the original ruby read method.

  def sysread(length)
    neverblock? ? read_neverblock(length) : rb_sysread(length)
  end

  def read(length = nil, sbuffer = nil)
    return rb_read(length, sbuffer) if file?
    return '' if length == 0

    if sbuffer.nil?
      sbuffer = ''
    else
      sbuffer = sbuffer.to_str
      sbuffer.delete!(sbuffer)
    end
    if length.nil?
      # we need to read till end of stream
      loop do
        sbuffer << sysread(NB_BUFFER_LENGTH)
      rescue EOFError
        break
      end
      return sbuffer
    else # length != nil
      if buffer.length >= length
        sbuffer << buffer.slice!(0, length)
        return sbuffer
      elsif buffer.length > 0
        sbuffer << buffer
      end
      self.buffer = ''
      remaining_length = length - sbuffer.length
      while sbuffer.length < length && remaining_length > 0
        begin
          sbuffer << sysread(NB_BUFFER_LENGTH < remaining_length ? remaining_length : NB_BUFFER_LENGTH)
          remaining_length -= sbuffer.length
        rescue EOFError
          break
        end # begin
      end # while
    end # if length
    return nil if sbuffer.length.zero? && length > 0
    return sbuffer if sbuffer.length <= length

    buffer << sbuffer.slice!(length, sbuffer.length - 1)
    sbuffer
  end

  def readpartial(length = nil, sbuffer = nil)
    raise ArgumentError if !length.nil? && length < 0

    if sbuffer.nil?
      sbuffer = ''
    else
      sbuffer = sbuffer.to_str
      sbuffer.delete!(sbuffer)
    end

    sbuffer << if buffer.length >= length
                 buffer.slice!(0, length)
               elsif buffer.length > 0
                 buffer.slice!(0, buffer.length - 1)
               else
                 rb_sysread(length)
               end
    sbuffer
  end

  def write_neverblock(data)
    written = 0
    begin
      old_flags = get_flags
      data &&= data.to_s
      written += write_nonblock(data[written, data.length])
      set_flags(old_flags)
      raise Errno::EAGAIN if written < data.length
    rescue Errno::EWOULDBLOCK, Errno::EAGAIN, Errno::EINTR
      set_flags(old_flags)
      NB.wait(:write, self)
      retry
    end
    written
  end

  def syswrite(*args)
    return rb_syswrite(*args) unless neverblock?

    write_neverblock(*args)
  end

  def write(data)
    return 0 if data.to_s.empty?
    return rb_write(data) if file?
    return rb_write(data) if self == STDOUT

    syswrite(data)
  end

  def gets(sep = $/)
    puts 'NEVERBLOCK gets'

    logger = Logger.new(STDOUT)
    logger.level = Logger::WARN
    logger.info('ARGS TO GETS METHOD')
    logger.info(sep)

    return rb_gets(sep) if file?

    res = ''
    sep = "\n\n" if sep == ''
    sep = $/ if sep.nil?
    while res.index(sep).nil?
      break if (c = read(1)).nil?

      res << c
    end
    return nil if res.empty?

    $_ = res
    res
  end

  def readlines(sep = $/)
    return rb_readlines(sep) if file?

    res = []
    begin
      loop { res << readline(sep) }
    rescue EOFError
    end
    res
  end

  def readchar
    return rb_readchar if file?

    ch = read(1)
    raise EOFError if ch.nil?

    ch
  end

  def getc
    return rb_getc if file?

    begin
      res = readchar
    rescue EOFError
      res = nil
    end
  end

  def readline(sep = $/)
    return rb_readline(sep) if file?

    res = gets(sep)
    raise EOFError if res.nil?

    res
  end

  def print(*args)
    return rb_print if file?

    args.each { |element| syswrite(element) }
  end

  def puts(*args)
    rb_syswrite(args.join("\n") + "\n")
  end

  def neverblock?
    !file? && NB.neverblocking?
  end

  def p(obj)
    rb_syswrite(obj.inspect + "\n")
  end

  protected

  def get_flags
    fcntl(Fcntl::F_GETFL, 0)
  end

  def set_flags(flags)
    fcntl(Fcntl::F_SETFL, flags)
  end

  def buffer
    @buffer ||= ''
  end

  attr_writer :buffer

  def file?
    @file ||= stat.file?
  end
end
