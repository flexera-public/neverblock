require 'eventmachine'
require 'thread'

module NeverBlock

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

  def self.remove_handler(handler)
    if @@handlers[handler.fd] == handler
      @@handlers.delete(handler.fd)
      handler.detach
    end
  end

  def self.sleep(time)
    return if time.nil? || time <= 0

    NB.logger.warn("NB> NB.sleep called within timeout #{NB::Fiber.current[:nb_timeout].inspect}. Backtrace: #{caller.join("\n")}") if NB::Fiber.current[:nb_timeout]
    fiber = NB::Fiber.current
    NB.reactor.add_timer(time) do
      fiber.resume
    end

    NB::Fiber.yield
  end

  def self.yield
    fiber = NB::Fiber.current

    NB.logger.warn("NB> NB.yield called within timeout #{NB::Fiber.current[:nb_timeout].inspect}. Backtrace: #{caller.join("\n")}") if NB::Fiber.current[:nb_timeout]
    EM.many_ticks do
      fiber.resume
    end

    NB::Fiber.yield
  end
end
