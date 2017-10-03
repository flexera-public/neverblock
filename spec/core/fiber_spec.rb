require_relative "../spec_helper"

describe NeverBlock::Fiber do
  context "with mutex" do
    before(:each) { @mutex = Mutex.new }
    it "turns off neverblock in synchronize section" do
      results = []
      EM.run do
        fiber_pool = NB::FiberPool.new(1)
        fiber_pool.spawn do
          results << NB.neverblocking?
          @mutex.synchronize do
            results << NB.neverblocking?
          end
          results << NB.neverblocking?
        end
        fiber_pool.spawn { EM.stop }
      end
      results.should == [true, false, true]
    end

    it "handles multiple mutexes" do
      results = []
      @mutex2 = Mutex.new
      EM.run do
        fiber_pool = NB::FiberPool.new(1)
        fiber_pool.spawn do
          results << NB.neverblocking?
          @mutex.synchronize do
            results << NB.neverblocking?
            @mutex2.synchronize do
              results << NB.neverblocking?
            end
            results << NB.neverblocking?
          end
          results << NB.neverblocking?
        end
        fiber_pool.spawn { EM.stop }
      end
      results.should == [true, false, false, false, true]
    end

    it "recovers from errors in synchronize" do
      results = []
      EM.run do
        fiber_pool = NB::FiberPool.new(5)
        fiber_pool.spawn do
          results << NB.neverblocking?
          begin
            @mutex.synchronize do
              results << NB.neverblocking?
              raise "ERROR"
            end
          rescue
          end
          results << NB.neverblocking?
        end
        fiber_pool.spawn { EM.stop }
      end
      results.should == [true, false, true]
    end

    # For something like a logger may be background threads calling the logger's
    # mutex to synchronize log calls. Those other threads shouldn't affect
    # the main event loop thread.
    it "turns off neverblock when mutex is locked" do
      results = []
      results_by_thread = {}
      EM.run do
        fiber_pool = NB::FiberPool.new(5)
        fiber_pool.spawn do
          results << NB.neverblocking? # expect true
          @mutex.lock
          threads = []
          5.times do
            threads << Thread.new do
              @mutex.lock
              results_by_thread[Thread.current.object_id] = NB.neverblocking?
              @mutex.unlock
            end
          end
          results << NB.neverblocking? # expect false
          @mutex.unlock
          threads.each(&:join)

          results << NB.neverblocking? # expect true
        end
        fiber_pool.spawn { EM.stop }
      end
      results.should == [true, false, true]
      results_by_thread.values.each do |results|
        results.should == false
      end
    end

    # For something like a logger may be background threads calling the logger's
    # mutex to synchronize log calls. Those other threads shouldn't affect
    # the main event loop thread.
    it "handles conditional variables (which use mutex.sleep)" do
      results = []
      @cv = ConditionVariable.new
      EM.run do
        fiber_pool = NB::FiberPool.new(5)
        fiber_pool.spawn do
          results << NB.neverblocking? # expect true
          @mutex.lock
          results << NB.neverblocking? # expect false
          t = Thread.new do
            @mutex.synchronize do
              results << NB.neverblocking? # expect false
              @cv.signal
            end
          end
          @cv.wait(@mutex) # Calls @mutex.sleep and waits for thread to call signal
          results << NB.neverblocking? # expect false
          @mutex.unlock
          results << NB.neverblocking? # expect true
        end
        fiber_pool.spawn { EM.stop }
      end
      results.should == [true, false, false, false, true]
    end

  end
end
