require 'mhl/generic_swarm'


module MHL
  class ChargedSwarm < GenericSwarmBehavior

    attr_reader :particles
    # default composition is half charged, i.e., QPSO, and half neutral, i.e.,
    # traditional PSO (with inertia), swarms
    DEFAULT_CHARGED_TO_NEUTRAL_RATIO = 1.0

    def initialize(size:, initial_positions:, initial_velocities:,
                   charged_to_neutral_ratio: nil, alpha: nil, c1: nil, c2: nil,
                   chi: nil, constraints: nil, logger: nil)
      @size = size

      # retrieve ratio between charged (QPSO) and neutral (constrained PSO) particles
      ratio = (charged_to_neutral_ratio || DEFAULT_CHARGED_TO_NEUTRAL_RATIO).to_f
      unless ratio > 0.0
        raise ArgumentError, 'Parameter :charged_to_neutral_ratio should be a real greater than zero!'
      end

      num_charged_particles = (@size * ratio).round
      @num_neutral_particles = @size - num_charged_particles

      # the particles are ordered, with neutral (PSO w/ inertia) particles
      # first and charged (QPSO) particles later
      @particles = Array.new(@size) do |index|
        if index < @num_neutral_particles
          Particle.new(initial_positions[index], initial_velocities[index])
        else
          QuantumParticle.new(initial_positions[index])
        end
      end

      # find problem dimension
      @dimension  = initial_positions[0].size

      @iteration = 1

      # define procedure to get dynamic value for alpha
      @get_alpha = if alpha and alpha.respond_to? :call
        alpha
      else
        ->(it) { (alpha || DEFAULT_ALPHA).to_f }
      end

      # get values for parameters C1 and C2
      @c1 = (c1 || DEFAULT_C1).to_f
      @c2 = (c2 || DEFAULT_C2).to_f

      # define procedure to get dynamic value for chi
      @get_chi = if chi and chi.respond_to? :call
        chi
      else
        ->(it) { (chi || DEFAULT_CHI).to_f }
      end

      @constraints = constraints
      @logger = logger

      if @constraints and @logger
        @logger.info "ChargedSwarm called w/ constraints: #{@constraints}"
      end
    end

    # convert all particles to Quantum Particle
    def convert_quantum
      new_particles = []
      @particles.each do |p|
        new_particles << QuantumParticle(p.position)
      end
      @particles = new_particles
    end

    def mutate
      # get alpha parameter
      alpha = @get_alpha.call(@iteration)

      # get chi parameter
      chi = @get_chi.call(@iteration)

      # this calculates the C_n parameter (the centroid of the set of all the
      # particle attractors) as defined in equations 4.81 and 4.82 of [SUN11].
      #
      # Note: we consider ALL the particles here, not just the charged (QPSO)
      # ones. As a result, the neutral particles influence the behavior of the
      # charged ones not only by defining the swarm attractor, but also the
      # centroid.
      attractors = @particles.map {|p| p.attractor[:position] }
      c_n = 0.upto(@dimension-1).map do |j|
        attractors.inject(0.0) {|s,attr| s += attr[j] } / @size.to_f
      end

      @particles.each_with_index do |p,i|
        # remember: the particles are kept in a PSO-first and QPSO-last order
        if i < @num_neutral_particles
          p.move(chi, @c1, @c2, @swarm_attractor)
        else
          p.move(alpha, c_n, @swarm_attractor)
        end
        if @constraints
          p.remain_within(@constraints)
        end
      end

      @iteration += 1
    end
  end
end
