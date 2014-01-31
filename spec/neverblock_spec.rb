require_relative "spec_helper"

describe NeverBlock do
  context "timeout_for_rbuf_fill" do

    it "no error if doesn't timeout" do
      i = 0
      NB.timeout_for_rbuf_fill(1) { i += 1 }
      i.should == 1
    end

    it "times-out with Timeout::Error for Ruby 1.9" do
      stub_const("RUBY_VERSION", '1.9.3')
      verify_times_out_with_error(Timeout::Error)
    end

    it "times-out with Net::ReadTimeout for Ruby 2.0" do
      stub_const("RUBY_VERSION", '2.0.0')
      stub_const("Net::ReadTimeout", StandardError)
      verify_times_out_with_error(Net::ReadTimeout)
    end

    def verify_times_out_with_error(error_class)
      i = 0
      lambda do
        NB.timeout_for_rbuf_fill(0.01) do
          i += 1
          sleep(0.02)
          i += 1
        end
      end.should raise_error(error_class)
      i.should == 1
    end

  end
end