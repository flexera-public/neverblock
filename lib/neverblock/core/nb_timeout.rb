module NeverBlock
  class NbTimeout
    attr_accessor :time, :error_class
    def initialize(time, error_class)
      @time        = time
      @error_class = error_class
    end
  end
end