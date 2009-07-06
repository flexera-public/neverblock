# Author::    Mohammad A. Ali  (mailto:oldmoe@gmail.com)
# Copyright:: Copyright (c) 2008 eSpace, Inc.
# License::   Distributes under the same terms as Ruby

$:.unshift File.expand_path(File.dirname(__FILE__))

module NeverBlock
end

NB = NeverBlock

require 'core/reactor'
require 'core/system'
require 'core/io/fibered_connection_pool'
require 'core/concurrent/fiber_pool'

module NeverBlock

  # Checks if we should be working in a non-blocking mode
  def self.neverblocking?
    NB::Fiber.respond_to?(:current) && NB::Fiber.current[:neverblock]
  end

  # The given block will run its queries either in blocking or non-blocking
  # mode based on the first parameter
  def self.neverblock(nb = true, &block)
    status = NB::Fiber.current[:neverblock]
    NB::Fiber.current[:neverblock] = nb
    block.call
    NB::Fiber.current[:neverblock] = status
  end

  # Exception to be thrown for all neverblock internal errors
  class NBError < StandardError
  end

end

