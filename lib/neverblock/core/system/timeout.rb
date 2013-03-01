require 'timeout'

module Timeout

  class TimeoutHandler
    attr_reader :timeout_timer
    attr_reader :registered_calls
    attr_reader :fiber

    def initialize(timeout_timer, fiber)
      @timeout_timer    = timeout_timer
      @fiber            = fiber
      @registered_calls = []
      @status = :active
    end

    def active?
      @status == :active
    end

    def register(type, call_to_register=nil)
      @registered_calls << [type, call_to_register]
    end

    def deregister(type)
      @registered_calls.delete_if{|registered_call_type, registered_call| registered_call_type == type}
    end

    def cancel
      cancel_timer
      cancel_registered_calls
    end

    def cancel_timer
      @status = :canceled
      EM.cancel_timer(@timeout_timer)
    end

    def cancel_registered_calls
      @status = :canceled
      while registered_call = @registered_calls.shift
        type, registered_call = registered_call

        case type
        when :io_reader, :io_writer
          registered_call.remove_waiter(@fiber)
        when :sleep_timer
          EM.cancel_timer(registered_call)
        end
      end
    end

    def self.cancel_nested_timeout_handlers(timeout_handlers, current_timeout_handler, &block)
      # If the current_timeout_handler is still active, then cancel the nested timeout_handlers
      if (idx = timeout_handlers.index(current_timeout_handler))
        timeout_handlers_to_cancel = timeout_handlers.slice!(idx..timeout_handlers.size-1)
        timeout_handlers_to_cancel.each {|t| t.cancel }

        block.call
      end
    end
  end

  alias_method :rb_timeout, :timeout

  def timeout(time, klass=Timeout::Error, &block)
    return rb_timeout(time, klass,&block) unless NB.neverblocking?

    if time.nil? || time <= 0
      return block.call
    end

    fiber = NB::Fiber.current
    timeout_handlers = (fiber[:timeouts] ||= [])
    timeout_handler = nil

    timer = EM.add_timer(time) {
      # Because IO handling is scheduled using EM.many_ticks, we need
      # to schedule timeouts with EM.many_ticks as well, to ensure they fire
      # only after the operation would have been scheduled.
      # 
      # Otherwise, if the timeout was scheduled to fire in the same tick that the 
      # IO was ready, it would be possible to fire the timeout *before* 
      # continuing with the operation. 
      #
      # We want to ensure that any timeouts would be scheduled only *after* their 
      # covering operation has a chance to complete successfully.
      EM.many_ticks {
        # if we don't find our timer in the list of timeouts on the fiber
        # it means the operation must already have completed succesfully,
        # in other words: this is not the timeout you're looking for.
        TimeoutHandler.cancel_nested_timeout_handlers(timeout_handlers, timeout_handler) do
          timeout_handler.cancel
          fiber.resume(klass.new)
        end
      }
    }

    timeout_handler = TimeoutHandler.new(timer, fiber)
    timeout_handlers << timeout_handler

    ret = nil

    begin
      ret = block.call
    rescue Exception => e
      raise e
    ensure
      # cleanup nested timeouts....
      # remove this timeout and any timeouts that were added *after* it.
      # NOTE: this has *nothing* to do with the time of the timeouts. It is purely
      # the order-of-creation we are concerned with. Any timeouts created after
      # this one must be lingering garbage that should have been cleaned up already.
      # lingering garbage timers added after us that should have been cleaned up already...
      #
      # Note: that I can't think of a case when it would be possible to have
      # nested timeouts but I guess we can keep the code around just in case.
      TimeoutHandler.cancel_nested_timeout_handlers(timeout_handlers, timeout_handler) do
        # cleanup after ourselves
        timeout_handlers.delete(timer)
        timeout_handler.cancel
      end
    end

    ret
  end

  module_function :timeout
  module_function :rb_timeout

end
