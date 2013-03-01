require 'eventmachine'
require 'thread'

module NeverBlock

  module EMHandler
    def initialize(fd)
      @fd = fd
      @readers = []
      @writers = []
    end

    def add_writer(fiber)
      fiber[:io] = self
      self.notify_writable = true

      @writers << NB.register_with_timeout_handler(:io_writer, fiber)
    end

    def add_reader(fiber)
      fiber[:io] = self
      self.notify_readable = true

      @readers << NB.register_with_timeout_handler(:io_reader, fiber)
    end

    def remove_waiter(fiber)
      @readers.delete_if{|reader| reader[:fiber] == fiber}
      @writers.delete_if{|writer| writer[:fiber] == fiber}
    end

    def notify_readable
      if reader = @readers.shift
        EM.many_ticks {
          NB.deregister_timeout_handler(:io_reader, writer[:timeout_handler]) do
            reader[:fiber].resume
          end
        }
      else
        self.notify_readable = false
      end
      detach_if_done
    end

    def notify_writable
      if writer = @writers.shift
        EM.many_ticks {
          NB.deregister_timeout_handler(:io_writer, writer[:timeout_handler]) do
            writer[:fiber].resume
          end
        }
      else
        self.notify_writable = false
      end
      detach_if_done
    end
    
    # If the underlying descriptor is deleted before we got a chance
    # to detach then force removal
    def unbind
      NB.remove_handler(@fd)
    end

    def detach_if_done
      NB.remove_handler(@fd) if @readers.empty? && @writers.empty?
    end

  end

  def self.reactor
    EM
  end

  @@handlers = {}

  def self.wait(mode, io)
    fiber = NB::Fiber.current

    meth = case mode
    when :read
      :add_reader
    when :write
      :add_writer
    else
      raise "Invalid mode #{mode.inspect}"
    end

    fd = io.respond_to?(:to_io) ? io.to_io : io

    handler = (@@handlers[fd.fileno] ||= EM.watch(fd, EMHandler, fd.fileno))
    handler.send(meth, fiber)
    NB::Fiber.yield
  end

  def self.remove_handler(fd)
    if handler = @@handlers.delete(fd)
      handler.detach
    end
  end

  def self.sleep(time)
    NB::Fiber.yield if time.nil?
    return if time <= 0 
    fiber = NB::Fiber.current

    timeout_handler = fiber[:timeouts] && fiber[:timeouts].last
    timer = NB.reactor.add_timer(time) do
      deregister_timeout_handler(:sleep_timer, timeout_handler) do
        fiber.resume
      end
    end

    if timeout_handler
      timeout_handler.register(:sleep_timer, timer)
    end

    NB::Fiber.yield
  end

  def self.yield
    fiber = NB::Fiber.current
    timeout_handler = register_with_timeout_handler(:yield, fiber)[:timeout_handler]
    EM.many_ticks do
      deregister_timeout_handler(:yield, timeout_handler) do
        fiber.resume
      end
    end
    NB::Fiber.yield
  end

  def self.deregister_timeout_handler(type, timeout_handler, &block)
    if timeout_handler
      timeout_handler.deregister(type)
      if timeout_handler.active?
        block.call
      end
    else
      block.call
    end
  end

  def self.register_with_timeout_handler(type, fiber, call_to_register = nil)
    assignment = {:fiber => fiber}

    if timeout_handler = fiber[:timeouts] && fiber[:timeouts].last
      timeout_handler.register(type, call_to_register)

      assignment[:timeout_handler] = timeout_handler
    end

    assignment
  end

end
