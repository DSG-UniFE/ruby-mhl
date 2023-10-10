require 'forwardable'

module MHL
  class GenericSwarmBehavior

    # The following values are considered a best practice [SUN11] [CLERC02]
    # [BLACKWELLBRANKE04].
    # C_1 is the cognitive acceleration coefficient
    DEFAULT_C1 = 2.05
    # C_2 is the social acceleration coefficient
    DEFAULT_C2 = 2.05
    # \chi is the constraining factor for normal particles
    PHI = DEFAULT_C1 + DEFAULT_C2
    DEFAULT_CHI = 2.0 / (2 - PHI - Math.sqrt((PHI ** 2 - 4.0 * PHI))).abs

    # \alpha is the contraction-expansion (CE) coefficient for quantum
    # particles [SUN11].
    # In order for the QPSO algorithm to converge, \alpha must be lower than
    # $e^{\gamma} \approx 1.781$, where $\gamma \approx 0.5772156649$ is the
    # Euler constant. According to [SUN11], 0.75 looks like a sensible default
    # parameter.
    DEFAULT_ALPHA = 0.75

    extend Forwardable
    def_delegators :@particles, :each
    attr_reader :swarm_attractor,:bestfit

    include Enumerable

    def update_attractor
      # get the particle attractors
      particle_attractors = @particles.map { |p| p.attractor }

      # update swarm attractor (if needed)
      unless (defined?(@swarm_attractor))
        @swarm_attractor = particle_attractors.max_by {|p| p[:height] }
      else
        @swarm_attractor = [ @swarm_attractor, *particle_attractors ].max_by {|p| p[:height] }
      end
      @bestfit = @swarm_attractor[:height]
      @swarm_attractor
    end
  end
end
