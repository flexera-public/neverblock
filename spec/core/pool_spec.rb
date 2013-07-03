require_relative "../spec_helper"

describe NeverBlock::FiberPool do
  describe "fiber's main loop" do
    context "with outstanding work" do
      it "should give working fibers time to complete before picking up the next task" do
        expected_completion_order = [[:task1, 1], [:task2, 2], [:task3, 1]]
        completion_order = []
        EM.run do
          fiber_pool = NB::FiberPool.new(2)

          fiber_pool.spawn do
            NB.yield # so that more work can be scheduled
            completion_order << [:task1, NB::Fiber.current[:nb_fiber_pool_idx]]
          end

          fiber_pool.spawn do
            NB.yield # so that more work can be scheduled
            completion_order << [:task2, NB::Fiber.current[:nb_fiber_pool_idx]]
          end

          fiber_pool.spawn do
            completion_order << [:task3, NB::Fiber.current[:nb_fiber_pool_idx]]
            EM.stop
          end
        end

        completion_order.should == expected_completion_order
      end
    end
  end
end
