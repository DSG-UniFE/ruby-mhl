require 'matrix'
require 'securerandom'

require 'mhl/generic_particle'

module MHL
  class QuantumParticle < GenericParticle
    attr_reader :position

    # move particle using QPSO - Type II algorithm
    def move(alpha, mean_best, swarm_attractor)
      raise 'Particle attractor is nil!' if @attractor.nil?
      # raise 'Swarm attractor is nil!' if swarm_attractor.nil?

      dimension = @position.size

      # phi represents the \phi_{i,n} parameter in [SUN11], formula 4.83
      phi = Array.new(dimension) { SecureRandom.random_number }

      # p_i represents the p_{i,n} parameter in [SUN11], formulae 4.82 and 4.83
      p_i =
        Vector[*phi.zip(@attractor[:position]).map {|phi_j,p_j| phi_j * p_j }] +
        Vector[*phi.zip(swarm_attractor[:position]).map {|phi_j,g_j| (1.0 - phi_j) * g_j }]

      # delta represents the displacement for the current position.
      # See [SUN11], formula 4.82
      delta =
        @position.zip(mean_best).map {|x,y| alpha * (x-y).abs }.  # \alpha * | X_{i,n} - C_n |
        map {|x| x * Math.log(1.0 / SecureRandom.random_number) } # log(\frac{1}{u_{i,n+1}})

      # update position
      if SecureRandom.random_number < 0.5
        @position = p_i + Vector[*delta]
      else
        @position = p_i - Vector[*delta]
      end
    end

  end
end
