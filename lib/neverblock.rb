require 'net/http'

# Author::    Mohammad A. Ali  (mailto:oldmoe@gmail.com)
# Copyright:: Copyright (c) 2008 eSpace, Inc.
# License::   Distributes under the same terms as Ruby
module NeverBlock
  require 'logger'

  def self.logger=(logger)
    @logger = logger
  end

  def self.logger
    @logger ||= Logger.new(STDOUT)
  end

  # Checks if we should be working in a non-blocking mode
  def self.neverblocking?
    NB::Fiber.current.respond_to?(:neverblock) && NB::Fiber.current.neverblock && NB.reactor.reactor_running?
  end

  # The given block will run its queries either in blocking or non-blocking
  # mode based on the first parameter
  def self.neverblock(nb = true, &block)
    status = NB::Fiber.neverblock
    NB::Fiber.neverblock = !!nb
    block.call
    NB::Fiber.neverblock = status
  end

  # Exception to be thrown for all neverblock internal errors
  class NBError < StandardError
  end

  # Helper method for Net::BufferedIO#rbuf_fill monkey-patch.
  # Calls Timeout.timeout, but passes ReadTimeout parameter for Ruby 2.0 and above.
  def self.timeout_for_rbuf_fill(sec, &block)
    if RUBY_VERSION > '2.0'
      Timeout.timeout(sec, Net::ReadTimeout, &block)
    else
      Timeout.timeout(sec, &block)
    end
  end

end

NB = NeverBlock

require_relative 'neverblock/core/reactor'
require_relative 'neverblock/core/fiber'
require_relative 'neverblock/core/pool'

require_relative 'neverblock/core/nb_timeout'
require_relative 'neverblock/core/em_handler'
require_relative 'neverblock/core/watch_deferrable'

require_relative 'neverblock/core/system/system'
require_relative 'neverblock/core/system/timeout'


require_relative 'neverblock/io/socket'

require_relative 'neverblock/net/buffered_io'

require_relative 'neverblock/many_ticks'
require_relative 'neverblock/thin' if defined?(Thin)

