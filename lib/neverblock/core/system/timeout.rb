require 'timeout'

module Timeout

  alias_method :rb_timeout, :timeout

  def timeout(time, error_class=Timeout::Error, &block)
    return rb_timeout(time, error_class, &block) unless NB.neverblocking?

    fiber = NB::Fiber.current
    previous_timeout = fiber[:nb_timeout]
    NB.logger.warn("NB> Nested timeout detected with parent timeout=#{previous_timeout.inspect}, child timeout=#{[time, error_class].inspect}. Backtrace: #{caller.join("\n")}") if previous_timeout

    if time.nil? || time <= 0
      fiber[:nb_timeout] = nil
    else
      fiber[:nb_timeout] = NB::NbTimeout.new(time, error_class)
    end

    block.call
  ensure
    fiber[:nb_timeout] = previous_timeout if NB.neverblocking?
  end

  module_function :timeout
  module_function :rb_timeout

end
