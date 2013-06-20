require 'eventmachine'
require 'thread'

module NeverBlock

  module EMHandler
    attr_reader :fd

    def initialize(fd)
      @fd = fd
      @readers = []
      @writers = []
    end

    def setup_handler_deferrable(fiber)
      handler_deferrable = NB::WatchDeferrable.new(fiber, fiber[:nb_timeout])

      if nb_timeout = fiber[:nb_timeout]
        handler_deferrable.timeout(nb_timeout.time, nb_timeout)
      end

      # Anything that fails the handler_deferrable will trigger the errback
      handler_deferrable.errback do |status|
        if status == nb_timeout
          # Strictly speaking, we wouldn't have to remove any readers / writers from the handler because
          # calling succeed will just be a noop and the reactor would call notify_readable again in the next tick.
          # However, it is nice to be tidy and clean up stuff that is not needed anymore
          remove_waiter(handler_deferrable)

          # If the handler is not ready yet to read data, then we trigger the timeout
          fiber.resume(nb_timeout.error_class.new)
        else
          NB.logger.warn("NB> Called deferrable's errback with #{status.inspect} instead of nb_timeout: #{nb_timeout.inspect}. Fiber idx=#{handler_deferrable.fiber[:nb_fiber_pool_idx]}. Backtrace: #{caller.join("\n")}")
        end
      end

      handler_deferrable.callback do |*args|
        # In case many handler become available in the same tick, we use many_ticks
        # to give reactor time to do other work besides just reading.
        EM.many_ticks do
          fiber.resume
        end
      end

      handler_deferrable
    end

    def add_writer(fiber)
      handler_deferrable = setup_handler_deferrable(fiber)

      self.notify_writable = true
      @writers << handler_deferrable
    end

    def add_reader(fiber)
      handler_deferrable = setup_handler_deferrable(fiber)

      self.notify_readable = true
      @readers << handler_deferrable
    end

    def remove_waiter(handler_deferrable)
      @readers.delete(handler_deferrable)
      @writers.delete(handler_deferrable)

      detach_if_done
    end

    # Would be called in reactor.
    def notify_readable
      if handler_deferrable = @readers.shift
        handler_deferrable.succeed
      else
        self.notify_readable = false
      end

      detach_if_done
    end

    def notify_writable
      if handler_deferrable = @writers.shift
        handler_deferrable.succeed
      else
        self.notify_writable = false
      end

      detach_if_done
    end

    # If the underlying descriptor is deleted before we got a chance
    # to detach then force removal. Called by EM (socket closes).
    def unbind
      NB.remove_handler(self)
    end

    # Called by NB
    def detach_if_done
      NB.remove_handler(self) if @readers.empty? && @writers.empty?
    end

  end
end
