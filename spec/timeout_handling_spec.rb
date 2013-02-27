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

    it "should have all fibers ready and an empty queue initially" do
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
end

