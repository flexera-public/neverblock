def EM.many_ticks &blk
  (@tick_queue ||= []) << blk

  # Clean up otherwise when EM gets restarted, we would never restart the queue and the tick_queue could still
  # have scheduled ticks from the previous runs.
  @em_many_ticks_shutdown_hook ||= EM.add_shutdown_hook do
    @tick_queue_running = false
    @tick_queue = []
    @em_many_ticks_shutdown_hook = nil
  end

  unless @tick_queue_running
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
