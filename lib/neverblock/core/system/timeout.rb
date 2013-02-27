require 'timeout'

module Timeout

  alias_method :rb_timeout, :timeout

  def timeout(time, klass=Timeout::Error, &block)
    return rb_timeout(time, klass,&block) unless NB.neverblocking?

    if time.nil? || time <= 0
      return block.call
    end

    fiber = NB::Fiber.current
    timeouts = (fiber[:timeouts] ||= [])

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
        if (idx = timeouts.index(timer))
          timers_to_cancel = timeouts.slice!(idx..timeouts.size-1)
          timers_to_cancel.each {|t| EM.cancel_timer(t) }
          # remove fiber[:io] - this indicates to the many_ticks block not to resume!
          handler = fiber[:io]
          fiber[:io] = nil
          handler.remove_waiter(fiber) if handler

          sleep_timer = fiber[:sleep_timer]
          fiber[:sleep_timer] = nil
          EM.cancel_timer(sleep_timer) if sleep_timer

          fiber.resume(klass.new)
        end
      }
    }

    timeouts << timer

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
      if idx = timeouts.index(timer)
        timers_to_cancel = timeouts.slice!(idx..timeouts.size-1)
        timers_to_cancel.each {|t| EM.cancel_timer(t)}

        # cleanup after ourselves
        timeouts.delete(timer)

        EM.cancel_timer(timer)
      end
    end

    ret
  end

  module_function :timeout
  module_function :rb_timeout

end
