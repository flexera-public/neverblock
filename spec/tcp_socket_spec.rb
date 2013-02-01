require_relative "spec_helper"

def EM.spec
  EM.run {
    EM.add_timer(1) {
      raise "Spec took too long to run"
    }
    yield
  }
end

def fiber_aid
  NB::Fiber.new do
    begin
      yield

      EM.next_tick { EM.stop } # success so we can stop EM
    rescue => e
      # Make sure to raise the exception on the reactor
      EM.next_tick do
        raise e
      end
    end
  end.resume
end

describe TCPSocket, " without NeverBlock" do

  before(:all) do
    @server = TestServer.new :tcp_echo_server
    sleep 5
    @socket = TCPSocket.new "0.0.0.0", 8080
  end

  it "should connect, send, and receive data" do
    @socket.read(2).should == "hi"
    @socket.write "test"
    @socket.read(4).should == "test"
  end

  it "should not be mad concurrent" do
    start = Time.now
    20.times do
      socket = TCPSocket.new "0.0.0.0", 8080
      socket.read(2).should == "hi"
      socket.write "test"
      socket.read(4).should == "test"
    end
    (Time.now - start).should >=  1
  end

  after(:all) do
    @server.stop
  end

end

describe TCPSocket, " with NeverBlock" do

  before(:all) do
    @server = TestServer.new :tcp_echo_server
    sleep 5
  end
  before(:each) do
    @socket = TCPSocket.new "0.0.0.0", 8080
  end

  it "should connect, send, and receive data" do
    EM.spec {
      fiber_aid do
        @socket.read(2).should == "hi"
        @socket.write "test"
        @socket.read(4).should == "test"
      end
    }
  end

  it "should be mad concurrent" do
    EM.spec {
      @socket.read(2).should == "hi"

      start = Time.now
      10.times do
        fiber_aid do
          @socket.write "test"
          @socket.read(4).should == "test"
          (Time.now - start).should <= 0.3
        end
      end
    }
  end

  context "with a timeout" do
    context "and timeout expires and there is nothing read" do
      it "should raise a TimeoutError" do
        EM.spec {
          fiber_aid do
            lambda do
              @socket.read(2) # read 'hi' which gets posted by the echo server on startup
              Timeout.timeout(0.1, Timeout::Error) do
                @socket.read(2) # read more but now there is nothing to read... so it should timeout
              end
            end.should raise_error(Timeout::Error)
          end
        }
      end
    end
    context "and timeout expires and @socket is ready for read" do
      it "should not raise a TimeoutError since the data is read to be read" do
        EM.spec {
          fiber_aid do
            result = Timeout.timeout(0.1, Timeout::Error) do
              rb_sleep(1)
              @socket.read(2) # read more but now there is nothing to read... so it should timeout
            end
            result.should == "hi"
          end
        }
      end
    end
    context "and timeout does not expire and @socket is ready for read" do
      it "should not raise a TimeoutError since the data is read to be read" do
        EM.spec {
          fiber_aid do
            result = Timeout.timeout(10, Timeout::Error) do
              @socket.read(2) # read more but now there is nothing to read... so it should timeout
            end
            result.should == "hi"
          end
        }
      end
    end

    context "and nested timeouts with t1=0.1 and t2=5" do
      it "should not raise a TimeoutError if the data is read with t < 5" do
        EM.spec {
          @socket.read(2)
          fiber_aid do
            result = Timeout.timeout(0.1, Timeout::Error) do
              result = Timeout.timeout(5, Timeout::Error) do
                @socket.read(2) # read more but now there is nothing to read... so it should timeout
              end
            end
            result.should == "h2"
          end

          NB::Fiber.new do
            rb_sleep(0.2)
            @socket.write("h2")
          end.resume
        }
      end
    end
    context "and nested timeouts with t1=5 and t2=0.01" do
      it "should raise a TimeoutError since the data is not read with t < 0.01" do
        EM.spec do
          @socket.read(2)

          fiber_aid do
            lambda do
              Timeout.timeout(5) do
                result = Timeout.timeout(0.01) do
                  result = @socket.read(2) # read more but now there is nothing to read... so it should timeout
                end
              end
            end.should raise_error(Timeout::Error)
          end
          NB::Fiber.new do
            sleep(0.5)
            @socket.write("h2")
          end.resume
        end
      end
    end
    context "and a single timeouts with two @socket.read calls" do
      it "should apply the timeout length for each @socket.read" do
        EM.spec {
          @socket.read(2)

          fiber_aid do
            result = Timeout.timeout(0.6, Timeout::Error) do
              @socket.read(2) + @socket.read(2)
            end
            result.should == "h2h3"
          end

          NB::Fiber.new do
            sleep(0.4)
            @socket.write("h2")
            sleep(0.4)
            @socket.write("h3")
          end.resume
        }
      end
    end
    context "and a timeout for non-io" do
      it "should not apply the timeout and raise no Timeout::Error" do
        EM.spec {
          fiber_aid do
            lambda do
              Timeout.timeout(0.1, Timeout::Error) do
                sleep(0.5)
              end
            end.should_not raise_error(Timeout::Error)
          end
        }
      end
    end
  end


  after(:all) do
    @server.stop
  end
  
end
