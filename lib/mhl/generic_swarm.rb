require 'forwardable'

module MHL
  class GenericSwarmBehavior

    # The following values were taken from [BLACKWELLBRANKE04] Tim Blackwell,
    # Jürgen Branke, "Multi-swarm Optimization in Dynamic Environments",
    # Applications of Evolutionary Computing, pp.  489-500, Springer, 2004.
    # DOI: 10.1007/978-3-540-24653-4_50
    # C_1 is the cognitive acceleration coefficient
    DEFAULT_C1 = 2.05
    # C_2 is the social acceleration coefficient
    DEFAULT_C2 = 2.05
    PHI = DEFAULT_C1 + DEFAULT_C2
    # \omega is the inertia weight
    DEFAULT_OMEGA = 2.0 / (2 - PHI - Math.sqrt(PHI ** 2 - 4.0 * PHI)).abs

    # \alpha is the inertia weight
    # According to [SUN11], this looks like a sensible default parameter
    DEFAULT_ALPHA = 0.75

    extend Forwardable
    def_delegators :@particles, :each

    include Enumerable

    def update_attractor
      # get the particle attractors
      particle_attractors = @particles.map { |p| p.attractor }

      # update swarm attractor (if needed)
      if @swarm_attractor.nil?
        @swarm_attractor = particle_attractors.max_by {|p| p[:height] }
      else
        @swarm_attractor = [ @swarm_attractor, *particle_attractors ].max_by {|p| p[:height] }
      end

      @swarm_attractor
    end
  end
end
