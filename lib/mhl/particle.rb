require 'securerandom'

require 'mhl/generic_particle'

module MHL
  class Particle < GenericParticle
    def initialize(initial_position, initial_velocity)
      super(initial_position)
      @velocity = initial_velocity
    end

    # move particle and update attractor
    def move(chi, c1, c2, swarm_attractor)
      raise 'Particle attractor is nil!' if @attractor.nil?

      # update particle velocity and position according to the Constrained PSO
      # variant of the Particle Swarm Optimization algorithm:
      #
      # V_{i,j}(t+1) = \chi [ V_{i,j}(t) + \\
      #                       C_1 * r_{i,j}(t) * (P_{i,j}(t) - X_{i,j}(t)) + \\
      #                       C_2 * R_{i,j}(t) * (G_j(t) - X_{i,j}(t)) ] \\
      # X_{i,j}(t+1) = X_{i,j}(t) + V_{i,j}(t+1)
      #
      # see equation 4.30 of [SUN11].

      # update velocity
      @velocity = @velocity.zip(@position, @attractor[:position], swarm_attractor[:position]).map do |v_j,x_j,p_j,g_j|
        # everything is damped by inertia weight chi
        chi *
          #previous velocity
          (v_j +
          # "memory" component (linear attraction towards the best position
          # that this particle encountered so far)
          c1 * SecureRandom.random_number * (p_j - x_j) +
          # "social" component (linear attraction towards the best position
          # that the entire swarm encountered so far)
          c2 * SecureRandom.random_number * (g_j - x_j))
      end

      # update position
      @position = @position.zip(@velocity).map do |x_j,v_j|
        x_j + v_j
      end
    end

    # implement confinement à la SPSO 2011. for more information, see equations
    # 3.14 and 3.15 of [CLERC12].
    def remain_within(constraints)
      @position = @position.map.with_index do |x_j,j|
        d_max = constraints[:max][j]
        d_min = constraints[:min][j]
        if x_j > d_max
          # puts "resetting #{j}-th position component #{x_j} to #{d_max}"
          x_j = d_max
          # puts "resetting #{j}-th velocity component #{@velocity[j]} to #{-0.5 * @velocity[j]}"
          @velocity[j] = -0.5 * @velocity[j]
        elsif x_j < d_min
          # puts "resetting #{j}-th position component #{x_j} to #{d_min}"
          x_j = d_min
          # puts "resetting #{j}-th velocity component #{@velocity[j]} to #{-0.5 * @velocity[j]}"
          @velocity[j] = -0.5 * @velocity[j]
        end
        x_j
      end
    end

  end
end
