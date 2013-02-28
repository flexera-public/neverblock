require_relative "spec_helper"

module NeverBlockTimeoutSpec
  #Define different classes so that it is obvious which Timeout::Error got triggered.
  class T1TimeoutError < Timeout::Error; end
  class T2TimeoutError < Timeout::Error; end

  # Helper method to know which timers are pending. Used to figure out in which order
  # the timeout timers are ordered in the Fiber's cached timeout_timers.
  #
  # @params Array, timeout_timers are the timeout timers that the fiber has cached
  # @params Array, t1_t2_timers are the timers that got scheduled. First item is t1's timer and 2nd is t2's timer.
  # @return Array, array containing :t1_timer, :t2_timer and / or :unknown
  def self.timeout_timers_to_sym(timeout_timers, t1_t2_timers)
    t1_timer = t1_t2_timers.first
    t2_timer = t1_t2_timers.last

    timeout_timers.collect do |timeout_timer|
      if timeout_timer == t1_timer
        :t1_timer
      elsif timeout_timer == t2_timer
        :t2_timer
      else
        :unknown
      end
    end
  end

  def self.run_scenario(t1, t2, &block)
    EM.error_handler do |error|
      Merb.logger.error("ERROR Caught exception in EventMachine: #{error.inspect}")
      exit 1
    end

    results = []
    fiber_pool = NB::Pool::FiberPool.new(1)
    EM.run {
      fiber_pool.spawn do
        fiber = NB::Fiber.current
        timeout_timers = (fiber[:timeouts] ||= [])
        timers  = []

        results << {:action => :initial_state, :timeouts => timeout_timers_to_sym(timeout_timers, timers)}
        begin
          Timeout.timeout(t1, NeverBlockTimeoutSpec::T1TimeoutError ) {
            timers << timeout_timers.first
            results << {:action => :t1_start, :timeouts => timeout_timers_to_sym(timeout_timers, timers)}

            begin
              Timeout.timeout(t2, NeverBlockTimeoutSpec::T2TimeoutError ) {
                timers << timeout_timers.select{|t| !timers.include?(t)}.first
                results << {:action => :t2_start, :timeouts => timeout_timers_to_sym(timeout_timers, timers)}

                begin
                  block.call
                rescue => e
                  results << {:action => :t2_rescue, :timeouts => timeout_timers_to_sym(timeout_timers, timers), :exception => e.class}
                  raise e
                end

                results << {:action => :t2_end, :timeouts => timeout_timers_to_sym(timeout_timers, timers)}
              } # inner timeout t2
            rescue => e
              results << {:action => :t1_rescue, :timeouts => timeout_timers_to_sym(timeout_timers, timers), :exception => e.class}
              raise e
            end
            results << {:action => :t1_end, :timeouts => timeout_timers_to_sym(timeout_timers, timers)}
          } # outer timeout t1

        rescue => e
          results << {:action => :final_state, :timeouts => timeout_timers_to_sym(timeout_timers, timers), :exception => e.class}
        end

        results << {:action => :final_state, :timeouts => timeout_timers_to_sym(timeout_timers, timers)} if results.last[:action] != :final_state

        # Due to a bug in EM.many_ticks where its state is not cleaned up between EM runs,
        # we have to clean up its state before stopping EM.
        EM.instance_variable_set(:@tick_queue_running, false)
        EM.instance_variable_set(:@tick_queue, [])

        EM.stop {}
      end
    }

    results
  end

  def self.it_should_correctly_setup_timers(results)
    result = results.shift
    result[:action].should == :initial_state
    result[:timeouts].should == []

    result = results.shift
    # outer timeout block starts
    result[:action].should == :t1_start
    # with the new timeout block a EM timer gets scheduled
    result[:timeouts].should == [:t1_timer]

    result = results.shift
    # inner timeout block starts
    result[:action].should == :t2_start
    # with the new timeout block a 2nd EM timer gets scheduled
    result[:timeouts].should == [:t1_timer, :t2_timer]
  end
end

describe "NeverBlock::Timeout" do

  context "with t1=1 second, t2=2 seconds with sleep(5)" do
    before(:each) do
      @results = NeverBlockTimeoutSpec.run_scenario(t1=1, t2=2){ sleep(5) }
    end

    it "it should trigger outer timeout timer" do
      NeverBlockTimeoutSpec.it_should_correctly_setup_timers(@results)

      result = @results.shift

      # t1's timer gets triggered since sleep is longer than its timeout
      result[:action].should    == :t2_rescue
      # all timeouts after t1's timeout get canceled
      # t1's timeout gets canceled even though it is already completed
      result[:timeouts].should  == []
      # t2's timer calls fiber.resume(Timeout::Error.new) and exception gets raised
      # at the point where the fiber yielded (hence in the t2's sleep).
      # As a result, the exception gets caught in t2's rescue blocks
      result[:exception].should == NeverBlockTimeoutSpec::T1TimeoutError

      result = @results.shift
      # t2's timeout exception bubbles up and hits t1's rescue block.
      result[:action].should    == :t1_rescue
      # timeouts have already been canceled in previous step
      result[:timeouts].should  == []
      # t2's timeout exceptions gets caught again and re-raised in rescue block
      result[:exception].should == NeverBlockTimeoutSpec::T1TimeoutError

      result = @results.shift
      result[:action].should    == :final_state
      result[:timeouts].should  == []
      result[:exception].should == NeverBlockTimeoutSpec::T1TimeoutError

      @results.should == []
    end
  end

  context "with t1=2 second, t2=1 seconds with sleep(5)" do
    before(:each) do
      @results = NeverBlockTimeoutSpec.run_scenario(t1=2, t2=1){ sleep(5) }
    end

    it "it should trigger inner timeout timer" do
      NeverBlockTimeoutSpec.it_should_correctly_setup_timers(@results)

      result = @results.shift

      # t2's timer triggers first after 2 seconds.
      result[:action].should    == :t2_rescue
      # all timeouts after t2's timeout get canceled, hence none. t1_timer still exists.
      # t2's timeout gets canceled even though it is already completed.
      result[:timeouts].should  == [:t1_timer]
      # t2's timer calls fiber.resume(Timeout::Error.new) and exception gets raised
      # at the point where the fiber yielded (hence in the t2's sleep).
      result[:exception].should == NeverBlockTimeoutSpec::T2TimeoutError

      result = @results.shift
      # t2's timeout exception bubbles up and hits t1's rescue block.
      result[:action].should    == :t1_rescue
      # t1's timer still exists. Since block now returns (with an exception),
      # the call is complete and the t1_timer will get canceled before final_state.
      result[:timeouts].should  == [:t1_timer]
      # t2's timeout exceptions gets caught again and re-raised in rescue block of t1 timer's block.
      result[:exception].should == NeverBlockTimeoutSpec::T2TimeoutError

      result = @results.shift
      result[:action].should    == :final_state
      result[:timeouts].should  == []
      result[:exception].should == NeverBlockTimeoutSpec::T2TimeoutError

      @results.should == []
    end
  end
  context "with t1=1 second, t2=1 seconds with blocking sleep(2)" do
    before(:each) do
      @results = NeverBlockTimeoutSpec.run_scenario(t1=1, t2=1){ rb_sleep(2) }
    end

    it "it should trigger no timeout because call completed as both timeout timers could get triggered" do
      NeverBlockTimeoutSpec.it_should_correctly_setup_timers(@results)

      # t1_timer and t2_timer are setup and both would be ready to fire but the
      # rb_sleep has also completed. As a result, t1_timer and t2_timer should not
      # fire anymore.
      result = @results.shift
      result[:action].should    == :t2_end
      result[:timeouts].should  == [:t1_timer, :t2_timer]
      result[:exception].should == nil

      result = @results.shift
      result[:action].should    == :t1_end
      result[:timeouts].should  == [:t1_timer]
      result[:exception].should == nil

      result = @results.shift
      result[:action].should    == :final_state
      result[:timeouts].should  == []
      result[:exception].should == nil

      @results.should == []
    end
  end
  context "with t1=2 second, t2=1 seconds with blocking sleep(3) then sleep(10)" do
    before(:each) do
      @results = NeverBlockTimeoutSpec.run_scenario(t1=2, t2=1){ rb_sleep(3); sleep(10) }
    end

    it "it should trigger inner timeout timer because both timeout timers are ready in same tick but inner timeout timer has smaller timeout" do
      NeverBlockTimeoutSpec.it_should_correctly_setup_timers(@results)

      result = @results.shift

      # Both t2's timer as well as t1's timer would get triggered since rb_sleep was longer
      # than both timeouts. t2's timer triggers first due to smaller timeout.
      result[:action].should    == :t2_rescue
      # all timeouts after t2's timeout get canceled, hence none and t1_timer still exists.
      # t2's timeout gets canceled even though it is already completed.
      result[:timeouts].should  == [:t1_timer]
      # t2's timer calls fiber.resume(Timeout::Error.new) and exception gets raised
      # at the point where the fiber yielded (hence in the t2's sleep).
      result[:exception].should == NeverBlockTimeoutSpec::T2TimeoutError

      result = @results.shift
      # t2's timeout exception bubbles up and hits t1's rescue block.
      result[:action].should    == :t1_rescue
      # t1's timer still exists. Since block now returns (even with an exception),
      # the call is complete and the t1_timer will get canceled in the ensure block
      # before final_state.
      result[:timeouts].should  == [:t1_timer]
      # t2's timeout exceptions gets caught again and re-raised in rescue block of t1 timer's block.
      result[:exception].should == NeverBlockTimeoutSpec::T2TimeoutError

      result = @results.shift
      result[:action].should    == :final_state
      result[:timeouts].should  == []
      result[:exception].should == NeverBlockTimeoutSpec::T2TimeoutError

      @results.should == []
    end
  end

  context "with t1=1 second, t2=2 seconds with blocking sleep(3) then sleep(10)" do
    before(:each) do
      @results = NeverBlockTimeoutSpec.run_scenario(t1=1, t2=2){ rb_sleep(3); sleep(10); }
    end

    it "it should trigger outer timeout timer because both timeout timers are ready in same tick but outer timeout timer has smaller timeout" do
      NeverBlockTimeoutSpec.it_should_correctly_setup_timers(@results)

      result = @results.shift

      # Both t2's timer as well as t1's timer would get triggered since rb_sleep was longer
      # than both timeouts. t1's timer triggers first due to its smaller timeout.
      result[:action].should    == :t2_rescue
      # all timeouts after t1's timeout get canceled (t2_timer).
      # t1's timeout gets canceled even though it is already completed.
      result[:timeouts].should  == []
      # t1's timer calls fiber.resume(Timeout::Error.new) and exception gets raised
      # at the point where the fiber yielded (hence in the t2's sleep).
      result[:exception].should == NeverBlockTimeoutSpec::T1TimeoutError

      result = @results.shift
      # t1's timeout exception bubbles up and hits t1's rescue block.
      result[:action].should    == :t1_rescue
      # Since the inner block raised an exception, the rescue of the outer block gets
      # called and the ensure block afterwards. t1_timer was already canceled earlier
      # and the ensure block wont cancel it.
      result[:timeouts].should  == []
      # t2's timeout exceptions gets caught again and re-raised in rescue block of t1 timer's block.
      result[:exception].should == NeverBlockTimeoutSpec::T1TimeoutError

      result = @results.shift
      result[:action].should    == :final_state
      result[:timeouts].should  == []
      result[:exception].should == NeverBlockTimeoutSpec::T1TimeoutError

      @results.should == []
    end
  end
  context "with t1=1 second, t2=1 seconds with blocking sleep(3) then sleep(10)" do
    before(:each) do
      @results = NeverBlockTimeoutSpec.run_scenario(t1=1, t2=1){ rb_sleep(3); sleep(10) }
    end

    it "it should trigger outer timeout timer because both timeout timers are ready in same tick but outer timeout timer was scheduled first" do
      NeverBlockTimeoutSpec.it_should_correctly_setup_timers(@results)

      result = @results.shift

      # Both t2's timer as well as t1's timer would get triggered since rb_sleep was longer
      # than both timeouts. t1's timer triggers first since it was scheduled first.
      result[:action].should    == :t2_rescue
      # all timeouts after t1's timeout get canceled (t2_timer).
      # t1's timeout gets canceled even though it is already completed.
      result[:timeouts].should  == []
      # t1's timer calls fiber.resume(Timeout::Error.new) and exception gets raised
      # at the point where the fiber yielded (hence in the t2's sleep).
      result[:exception].should == NeverBlockTimeoutSpec::T1TimeoutError

      result = @results.shift
      # t1's timeout exception bubbles up and hits t1's rescue block.
      result[:action].should    == :t1_rescue
      # Since the inner block raised an exception, the rescue of the outer block gets
      # called and the ensure block afterwards. t1_timer was already canceled earlier
      # and the ensure block wont cancel it.
      result[:timeouts].should  == []
      # t2's timeout exceptions gets caught again and re-raised in rescue block of t1 timer's block.
      result[:exception].should == NeverBlockTimeoutSpec::T1TimeoutError

      result = @results.shift
      result[:action].should    == :final_state
      result[:timeouts].should  == []
      result[:exception].should == NeverBlockTimeoutSpec::T1TimeoutError

      @results.should == []
    end
  end

  context "with t1=3 second, t2=2 seconds with sleep(1)" do
    before(:each) do
      @results = NeverBlockTimeoutSpec.run_scenario(t1=3, t2=3){ sleep(1) }
    end

    it "it should trigger no timeout timers because the call completed before any timeouts" do
      NeverBlockTimeoutSpec.it_should_correctly_setup_timers(@results)

      result = @results.shift
      result[:action].should    == :t2_end
      result[:timeouts].should  == [:t1_timer, :t2_timer]
      result[:exception].should == nil

      result = @results.shift
      result[:action].should    == :t1_end
      result[:timeouts].should  == [:t1_timer]
      result[:exception].should == nil

      result = @results.shift
      result[:action].should    == :final_state
      result[:timeouts].should  == []
      result[:exception].should == nil

      @results.should == []
    end
  end
end

