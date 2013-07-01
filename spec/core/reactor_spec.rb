require_relative "../spec_helper"

describe NeverBlock do
  describe "::sleep" do
    context "with time nil" do
      before(:each) do
        @time = nil
      end
      it "should not sleep / yield" do
        expected_completion_order = [1, 2]

        completion_order = []
        EM.run do
          NB::Fiber.new do
            sleep(@time)
            completion_order << 1
          end.resume

          NB::Fiber.new do
            completion_order << 2

            EM.stop
          end.resume
        end

        completion_order.should == expected_completion_order
      end
    end

    context "with time <= 0" do
      before(:each) do
        @time = nil
      end
      it "should not sleep / yield" do
        expected_completion_order = [1, 2]

        completion_order = []
        EM.run do
          NB::Fiber.new do
            sleep(@time)
            completion_order << 1
          end.resume

          NB::Fiber.new do
            completion_order << 2

            EM.stop
          end.resume
        end

        completion_order.should == expected_completion_order
      end
    end

    context "with time > 0 " do
      before(:each) do
        @time = 0.1
      end
      it "should not sleep / yield" do
        expected_completion_order = [2, 1]

        completion_order = []
        EM.run do
          NB::Fiber.new do
            sleep(@time)
            completion_order << 1
            EM.stop
          end.resume

          NB::Fiber.new do
            completion_order << 2
          end.resume
        end

        completion_order.should == expected_completion_order
      end
    end

    context "with a timeout" do
      it "should ignore the timeout and log a warning" do
        EM.run do
          NB.logger.should_receive(:warn).twice

          NB::Fiber.new do
            Timeout.timeout(0.01) { sleep(0.1) }

            EM.stop
          end.resume
        end
      end
    end
  end

  describe "::yield" do
    it "should yield" do
      EM.run do
        fiber = NB::Fiber.new do
          NB.yield
          EM.stop
        end
        fiber.resume
      end
    end

    context "with a timeout" do
      it "should ignore the timeout and log a warning" do
        EM.run do
          NB.logger.should_receive(:warn).twice

          fiber = NB::Fiber.new do
            Timeout.timeout(0.01) do
              NB.yield
            end
            EM.stop
          end
          fiber.resume
        end
      end
    end
  end
end
