require_relative "spec_helper"

describe NeverBlock::FiberPool do
  before(:each) do
    @fiber_pool = NeverBlock::FiberPool.new(10)
  end

  it "should have all fibers ready and an empty queue initially" do
    @fiber_pool.fibers.length.should == 10
    @fiber_pool.instance_variable_get(:@queue).length.should == 0
  end

  it "should have fibers with @neverblock instance variable set to true" do
    @fiber_pool.fibers.each {|f| f.neverblock.should == true}
  end

  it "should process a new block if there are available fibers" do
    x = false
    @fiber_pool.spawn {x  = true}
    x.should == true
  end

  it "should queue requests if requests are more than fibers" do
    progress = Array.new(15, false)
    fibers = []
    @fiber_pool.fibers.each {|f| fibers << f}
    10.times do |i|
      # make all fibers busy
      @fiber_pool.spawn {Fiber.yield; progress[i] = true}
    end
    @fiber_pool.fibers.length.should == 0
    @fiber_pool.instance_variable_get(:@queue).length.should == 0

    #it should now queue
    @fiber_pool.spawn {progress[10] = true}
    @fiber_pool.fibers.length.should == 0
    @fiber_pool.instance_variable_get(:@queue).length.should == 1

    #resume the first fiber, this should also process the queued requests
    fibers[0].resume
    @fiber_pool.fibers.length.should == 0 # because there was more work and the fiber picked it up
    @fiber_pool.instance_variable_get(:@queue).length.should == 0

    fibers[0].resume
    @fiber_pool.fibers.length.should == 1 # because there was no more work
    [0, 10].each {|i| progress[i].should == true}
    (1..9).to_a.each {|i| progress[i].should == false}

    fibers_count = 1
    (1..9).to_a.each do |i|
      fibers[i].resume
      fibers_count = fibers_count + 1
      progress[i].should == true
      @fiber_pool.fibers.length.should == fibers_count
    end
    @fiber_pool.instance_variable_get(:@queue).length.should == 0
  end

  after(:each) do
    @fiber_pool = nil
  end

end

