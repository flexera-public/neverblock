module NeverBlock
  class WatchDeferrable
    include EM::Deferrable

    attr_accessor :fiber, :nb_timeout
    def initialize(fiber, nb_timeout=nil)
      @fiber       = fiber
      @nb_timeout  = nb_timeout
    end

    # Overriding timeout of Deferrable to delay the timeout by one tick.
    #
    # Setting a timeout on a Deferrable causes it to go into the failed state after
    # the Timeout expires (passing no arguments to the object's errbacks).
    # Setting the status at any time prior to a call to the expiration of the timeout
    # will cause the timer to be cancelled.
    def timeout seconds, *args
      cancel_timeout
      me = self

      @deferred_timeout = EventMachine::Timer.new(seconds) do
        # Delaying calling fail to the next tick since EM checks timers first, then IO, then next_ticks. So, if an IO
        # is ready but the timeout's timer is also ready, the timeout would win.
        EM.next_tick{ me.fail(*args) }
      end
      self
    end
  end
end