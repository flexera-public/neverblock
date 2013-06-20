require_relative "spec_helper"

describe "EM.many_ticks" do
  context "with a stopped EM runs and a scheduled many_ticks tick" do
    it "it should remove any outstanding ticks after EM has been stopped" do
      EM.run {
        # stop gets scheduled for the next tick.
        EM.stop
        # Starting a many_ticks tick in the next_tick as well which will get scheduled
        # in the next_tick after the 'EM.stop' and the tick_queue_running will get marked as running.
        # The scheduled many_ticks tick will however never happen because EM will get
        # stopped before.
        EM.many_ticks{} # scheduled in same tick as EM.stop but ahead of EM.stop
        EM.many_ticks{} # scheduled in many_tick's queue and should be cleared out after EM.stop was called
      }

      # After EM stopped it is important to clean up many_ticks. Otherwise scheduled
      # many_ticks will leave EM.many_ticks in a bad state where @tick_queue_running == true
      # but since EM has been stopped the scheduled many_ticks tick will never happen and
      # wont set @tick_queue_running back to true.
      #
      # If EM.many_ticks @tick_queue_running is not back to false, any scheduled
      # EM.many_ticks ticks wont ever get scheduled.
      EM.instance_variable_get(:@tick_queue).should be_empty
      EM.instance_variable_get(:@tick_queue_running).should == false
    end
  end
end

