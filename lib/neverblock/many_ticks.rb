def EM.many_ticks &blk
  (@tick_queue ||= []) << blk

  unless @tick_queue_running
    # Clean up otherwise when EM gets restarted, we would never restart the queue and the tick_queue could still
    # have scheduled ticks from the previous runs.
    EM.add_shutdown_hook do
      @tick_queue_running = false
      @tick_queue = []
    end

    @tick_queue_running = true

    pop = proc{
      begin
        @tick_queue.shift.call
      ensure
        if @tick_queue.any?
          EM.next_tick pop
        else
          @tick_queue_running = false
        end
      end
    }

    EM.next_tick pop
  end
end

def EM.many_ticks_queue_size
  (@tick_queue || []).size
end
