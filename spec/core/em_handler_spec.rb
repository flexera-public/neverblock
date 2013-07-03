require_relative "spec_helper"

class MyEMWatch < EM::Connection
  include NB::EMHandler
end

describe NB::EMHandler do
  describe "notify_readable" do
    before(:each) do
      @em_watch = MyEMWatch.new(0, 10)
      @fiber = {}
    end

    context "with a waiter" do
      before(:each) do
        @em_watch.add_reader(@fiber)
      end
      it "should resume the fiber only once" do
        @fiber.should_receive(:resume).once
        EM.should_receive(:many_ticks).and_return{|&block| block.call}

        # First time should call resume
        @em_watch.notify_readable
        # 2nd time should not call resume
        @em_watch.notify_readable
      end
    end

    context "with a timeout" do
      before(:each) do
        @error_class = Timeout::Error
        @fiber[:nb_timeout] = NB::NbTimeout.new(1, @error_class)

        NB::WatchDeferrable.any_instance.should_receive(:timeout).once
      end
      it "should resume with the timeout class" do
        @fiber.should_receive(:resume).once.with(an_instance_of(@error_class))

        @handler_deferrable = @em_watch.add_reader(@fiber).first
        @handler_deferrable.fail(@fiber[:nb_timeout]) # Timeout our deferrable

        @fiber.should_receive(:resume).never
        @em_watch.notify_readable
      end
    end

  end
end
