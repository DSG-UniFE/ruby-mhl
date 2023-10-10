module MHL

  class GenericParticle

    attr_reader :attractor,:position

    def initialize(initial_position)
      @position  = initial_position
      @attractor = nil
    end

    def evaluate(func)
      # calculate particle height
      @height = func.call(@position)

      # update particle attractor (if needed)
      if @attractor.nil? or @height > @attractor[:height]
        @attractor = { height: @height, position: @position }
      end
    end

  end

end
