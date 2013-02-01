module NeverBlock
  # Author::    Mohammad A. Ali  (mailto:oldmoe@gmail.com)
  # Copyright:: Copyright (c) 2008 eSpace, Inc.
  # License::   Distributes under the same terms as Ruby
  #
  #  A pool of initialized fibers
  #  It does not grow in size or create transient fibers
  #  It will queue code blocks when needed (if all its fibers are busy)
  #
  # This class is particulary useful when you use the fibers 
  # to connect to evented back ends. It also does not generate
  # transient objects and thus saves memory.
  #
  # Example:
  # fiber_pool = NeverBlock::FiberPool.new(150)
  # 
  # loop do
  #   fiber_pool.spawn do
  #     #fiber body goes here 
  #   end
  # end
  #
  class FiberPool

    # gives access to the currently free fibers
    attr_reader :fibers
    
    # ongoing work
    attr_reader :busy_fibers
    
    # pending work
    attr_reader :queue
    
    # full pool, doesn't change
    attr_reader :pool
    
    # Prepare a list of fibers that are able to run different blocks of code
    # every time. Once a fiber is done with its block, it attempts to fetch
    # another one from the queue
    def initialize(count = 50, logger=nil)
      @fibers,@busy_fibers,@queue,@on_empty,@pool = [],{},[],[],[]
      count.times do |i|
        fiber = NB::Fiber.new do |block|
          loop do
            begin
              block.call
            rescue => e
              if logger && logger.respond_to?(:error)
                logger.error("Exception caught in fiber pool: #{e.class.name}: #{e.message}")
                logger.error("Backtrace: #{e.backtrace.join("\n")}")
              end
            end
            unless @queue.empty?
              block = @queue.shift

              # If there are any other fibers working besides me, give them a chance to finish their work.
              NB.yield if @busy_fibers.size > 1
            else
              @busy_fibers.delete(NB::Fiber.current.object_id)
              @fibers << NB::Fiber.current
              @on_empty.shift.call while @on_empty.any? && @busy_fibers.empty?
              block = NB::Fiber.yield
            end
          end
        end

        fiber[:nb_fiber_pool_idx] = i

        @fibers << fiber
        @pool << fiber
      end
      
    end

    def on_empty(&blk)
      if @busy_fibers.empty?
        blk.call
      else
        @on_empty << blk
      end
    end

    # If there is an available fiber use it, otherwise, leave it to linger
    # in a queue
    def spawn(evented = true, &block)
      if fiber = @fibers.shift
        @busy_fibers[fiber.object_id] = fiber
        fiber[:neverblock] = evented
        fiber.resume(block)
      else
        @queue << block
      end
      self # we are keen on hiding our queue
    end

  end # FiberPool
  
  module Pool
    FiberPool = NeverBlock::FiberPool
  end
end # NeverBlock

