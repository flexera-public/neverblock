require_relative "../../spec_helper"

describe Timeout do
  describe "#timeout" do
    context "with nested timeouts" do
      it "should log a warning" do
        EM.run do
          NB.logger.should_receive(:warn).exactly(3).times

          NB::Fiber.new do
            Timeout.timeout(0.01) { Timeout.timeout(0.01) { x = 1 } }

            EM.stop
          end.resume
        end
      end
    end
  end
end
