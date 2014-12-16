module MHL

  class GenericParticle

    attr_reader :attractor

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

    def remain_within(constraints)
      new_pos = @position.map.with_index do |x,i|
        puts "resetting #{x} within #{constraints[:min][i]} and #{constraints[:max][i]}"
        d_max = constraints[:max][i]
        d_min = constraints[:min][i]
        d_size = d_max - d_min
        if x > d_max
          while x > d_max + d_size
            x -= d_size
          end
          if x > d_max
            x = 2 * d_max - x
          end
        elsif x < d_min
          while x < d_min - d_size
            x += d_size
          end
          if x < d_min
            x = 2 * d_min - x
          end
        end
        puts "now x is #{x}"
        x
      end
      puts "new_pos: #{new_pos}"
      @position = new_pos # Vector[new_pos]
    end

  end

end
