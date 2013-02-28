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
      @writers << fiber
    end

    def add_reader(fiber)
      fiber[:io] = self
      self.notify_readable = true
      @readers << fiber
    end

    def remove_waiter(fiber)
      @readers.delete(fiber)
      @writers.delete(fiber)
    end

    def notify_readable
      if f = @readers.shift
        # if f[:io] is nil, it means it was cleared by a timeout - dont resume!
        # make sure to set f[:io] to nil BEFORE resuming. if we set it after,
        # we'll clear any new value that was set during fiber.resume
        EM.many_ticks {
          if f[:io]
            f[:io] = nil
            f.resume
          end
        }
      else
        self.notify_readable = false
      end
      detach_if_done
    end

    def notify_writable
      if f = @writers.shift
        EM.many_ticks {
          if f[:io]
            f[:io] = nil
            f.resume
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
    fiber[:sleep_timer] = NB.reactor.add_timer(time) do
      # if f[:sleep_timer] is nil, it means it was cleared by a timeout - dont resume!
      # although since the timer should have been canceled by the timeout timer, we
      # should really never get into this situation.
      if fiber[:sleep_timer]
        # make sure to set f[:sleep_timer] to nil BEFORE resuming. if we set it after,
        # we'll clear any new value that was set during fiber.resume
        fiber[:sleep_timer] = nil
        fiber.resume
      end
    end
    NB::Fiber.yield
  end

  def self.yield
    fiber = NB::Fiber.current
    EM.many_ticks do
      # if f[:yield] is nil, it means it was cleared by a timeout - dont resume!
      if fiber[:yield]
        # make sure to set f[:io] to nil BEFORE resuming. if we set it after,
        # we'll clear any new value that was set during fiber.resume
        fiber[:yield] = nil
        fiber.resume
      end
    end
    NB::Fiber.yield
  end

end
