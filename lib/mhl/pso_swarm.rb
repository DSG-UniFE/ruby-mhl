require 'mhl/generic_swarm'
require 'mhl/particle'


module MHL
  class PSOSwarm < GenericSwarmBehavior

    def initialize(size:, initial_positions:, initial_velocities:, 
                   c1: nil, c2: nil, chi: nil, constraints: nil, logger: nil)
      @size      = size
      @particles = Array.new(@size) do |index|
        Particle.new(initial_positions[index], initial_velocities[index])
      end

      @iteration = 1

      # get values for parameters C1 and C2
      @c1 = (c1 || DEFAULT_C1).to_f
      @c2 = (c2 || DEFAULT_C2).to_f

      # define procedure to get dynamic value for chi
      @get_chi = if chi and chi.respond_to? :call
        chi
      else
        ->(iter) { (chi || DEFAULT_CHI).to_f }
      end

      @constraints = constraints
      @logger = logger

      if @constraints and @logger
        @logger.info "PSOSwarm called w/ constraints: #{@constraints}"
      end
    end

    def mutate(params={})
      # get chi parameter
      chi = @get_chi.call(@iteration)

      # move particles
      @particles.each_with_index do |p,i|
        p.move(chi, @c1, @c2, @swarm_attractor)
        if @constraints
          p.remain_within(@constraints)
        end
      end

      @iteration += 1
    end
  end
end
