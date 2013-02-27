def EM.many_ticks &blk
  (@tick_queue ||= []) << blk

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
