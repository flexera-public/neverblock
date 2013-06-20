module NeverBlock
  class WatchDeferrable
    include EM::Deferrable

    attr_accessor :fiber, :nb_timeout
    def initialize(fiber, nb_timeout=nil)
      @fiber       = fiber
      @nb_timeout  = nb_timeout
    end

  end
end