require 'securerandom'

require 'mhl/generic_particle'

module MHL
  class Particle < GenericParticle
    def initialize(initial_position, initial_velocity)
      super(initial_position)
      @velocity = initial_velocity
    end

    # move particle and update attractor
    def move(omega, c1, c2, swarm_attractor)
      raise 'Particle attractor is nil!' if @attractor.nil?
      # raise 'Swarm attractor is nil!' if swarm_attractor.nil?

      # update velocity
      @velocity =
        # previous velocity is damped by inertia weight omega
        omega * @velocity +
        # "memory" component (linear attraction towards the best position
        # that this particle encountered so far)
        c1 * SecureRandom.random_number * (attractor[:position] - @position) +
        # "social" component (linear attraction towards the best position
        # that the entire swarm encountered so far)
        c2 * SecureRandom.random_number * (swarm_attractor[:position] - @position)

      # update position
      @position = @position + @velocity
    end

  end
end
