require_relative "spec_helper"

module NeverBlockYieldSpec
  #Define different classes so that it is obvious which Timeout::Error got triggered.
  class T1TimeoutError < Timeout::Error; end
  class T2TimeoutError < Timeout::Error; end

  def self.run_scenario

    fiber_pool = NB::Pool::FiberPool.new(1)

    results = []

    EM.run {
      fiber_pool.spawn do


        begin
          # Tick 0:
          #  - add_timer
          #  - rb_sleep 2
          #  - NB.yield 1
          #      EM.many_ticks{resume for yield 1} where EM.many_ticks schedules the resume in next_tick (tick 1)
          #      yield 1 to EM
          #    end
          # --> many_ticks: [resume yield 1]
          # --> next_ticks: [resume yield 1]
          Timeout.timeout(t1=1, NeverBlockYieldSpec::T1TimeoutError) {
            # block till timeout timer is expired
            rb_sleep 2

            # yield 1
            NB.yield # end of tick 0 & start of tick 1

            # Tick 1:
            #  - resume for yield 1
            #  - NB.yield 2
            #      EM.many_ticks{resume for yield 2} where EM.many_ticks schedules the resume in next_tick (tick 2)
            #      yield 2 to EM
            #    end
            #  - trigger timeout
            #      EM.many_ticks{cancel_timers & resume(Timeout::Error)}
            #
            # --> many_ticks: [resume yield 2, cancel_timers & resume(Timeout::Error)]
            # --> next_tick: [resume yield 2]
            # yield 2
            NB.yield # end of tick 1 & start of tick 2

            # Tick 2:
            #  - resume for yield 2
            #  - NB.yield 3
            #      EM.many_ticks{resume for yield 3} where EM.many_ticks
            #      yield 3 to EM
            #    end
            #  - pop EM.many_ticks -> EM.next_tick{cancel_timers & resume(Timeout::Error)}
            #
            # --> many_ticks: [cancel_timers & resume(Timeout::Error), resume yield 3]
            # --> next_tick: [cancel_timers & resume(Timeout::Error)]
            # yield 3
            NB.yield # end of tick 2 & start of tick 3
          }
          results << {:action => :t1_end}
        rescue => e
          # --> many_ticks: [resume yield 3]
          # --> next_tick:  [resume yield 3]
          results << {:action => :t1_rescue, :exception => e.class}
        end


        begin
          Timeout.timeout(t2=1, NeverBlockYieldSpec::T2TimeoutError) {
            # Tick 3:
            #  - add_timer for sleep & yield
            #  - resume yield 3 -> wakes up sleep even though timer of sleep is far from ready
            #      # instead of this a the timeout timer should have been triggered since t2 < length of sleep
            # --> many_ticks: []
            # --> next_tick:  []
            sleep 10
          }
          results << {:action => :t2_end}
        rescue => e
          results << {:action => :t2_rescue, :exception => e.class}
        end

        EM.stop
      end
    }

    return results
  end

end

describe "yield" do
  context "with a yield's many_tick scheduled after its timeout timer" do
    before(:each) do
      @results = NeverBlockYieldSpec.run_scenario
    end
    it "it should cancel the scheduled many_tick after its timeout timer got triggered" do
      result = @results.shift
      result[:action].should    == :t1_rescue
      result[:exception].should == NeverBlockYieldSpec::T1TimeoutError

      result = @results.shift
      result[:action].should    == :t2_rescue
      result[:exception].should == NeverBlockYieldSpec::T2TimeoutError
    end
  end
end