# Author::    Mohammad A. Ali  (mailto:oldmoe@gmail.com)
# Copyright:: Copyright (c) 2009 eSpace, Inc.
# License::   Distributes under the same terms as Ruby

require 'fiber'

class NeverBlock::Fiber < Fiber

  def initialize(neverblock = true, &block)
    self[:neverblock] = neverblock
    super()
  end


  #Attribute Reference--Returns the value of a fiber-local variable, using
  #either a symbol or a string name. If the specified variable does not exist,
  #returns nil.
  def [](key)
    local_fiber_variables[key]
  end
  
  #Attribute Assignment--Sets or creates the value of a fiber-local variable,
  #using either a symbol or a string. See also Fiber#[].
  def []=(key,value)
    local_fiber_variables[key] = value
  end
  
  def self.resume(*args)
    NB.logger.error "DJR DJR NB resuming fiber"
    super
  end

  #Sending an exception instance to resume will yield the fiber
  #and then raise the exception. This is necessary to raise exceptions
  #in their correct context.
  def self.yield(*args)
    NB.logger.error "DJR DJR NB yielding in fiber"
    result = super
    raise result if result.is_a? Exception
    result
  end

  private
  
  def local_fiber_variables
    @local_fiber_variables ||= {}
  end

end

