module MHL
  class GenericParticle
    attr_reader :attractor, :position

    def initialize(initial_position)
      @position  = initial_position
      @attractor = nil
    end

    def evaluate(func)
      # calculate particle height
      @height = func.call(@position)

      # update particle attractor (if needed)
      return unless @attractor.nil? or @height > @attractor[:height]

      # store a defensive copy of the position to avoid corruption if
      # @position is later mutated in-place
      @attractor = { height: @height, position: @position.dup }
    end
  end
end
