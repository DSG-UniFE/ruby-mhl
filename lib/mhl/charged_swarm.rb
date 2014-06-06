require 'matrix'

require 'mhl/generic_swarm'


module MHL
  class ChargedSwarm < GenericSwarmBehavior

    # default composition is half charged, i.e., QPSO, and half neutral, i.e.,
    # traditional PSO (with inertia), swarms
    DEFAULT_CHARGED_TO_NEUTRAL_RATIO = 1.0

    def initialize(size, initial_positions, initial_velocities, params={})
      @size = size

      # retrieve ratio between charged (QPSO) and neutral (PSO w/ inertia) particles
      ratio = (params[:charged_to_neutral_ratio] || DEFAULT_CHARGED_TO_NEUTRAL_RATIO).to_f
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

      @generation = 1

      # define procedure to get dynamic value for alpha
      @get_alpha = if params.has_key? :alpha and params[:alpha].respond_to? :call
        params[:alpha]
      else
        ->(gen) { (params[:alpha] || DEFAULT_ALPHA).to_f }
      end

      # get values for parameters C1 and C2
      @c1 = (params[:c1] || DEFAULT_C1).to_f
      @c2 = (params[:c1] || DEFAULT_C2).to_f

      # define procedure to get dynamic value for omega
      @get_omega = if params.has_key? :omega and params[:omega].respond_to? :call
        params[:omega]
      else
        ->(gen) { (params[:omega] || DEFAULT_OMEGA).to_f }
      end
    end

    def mutate
      # get alpha parameter
      alpha = @get_alpha.call(@generation)

      # get omega parameter
      omega = @get_omega.call(@generation)

      # this calculates the C_n parameter (basically, the centroid of particle
      # attractors) as defined in [SUN11], formulae 4.81 and 4.82
      #
      # (note: the neutral particles influence the behavior of the charged ones
      # not only by defining the swarm attractor, but also by forming this centroid)
      c_n = @particles.inject(Vector[*[0]*@dimension]) {|s,p| s += p.attractor[:position] } / @size.to_f

      @particles.each_with_index do |p,i|
        # remember: the particles are kept in a PSO-first and QPSO-last order
        if i < @num_neutral_particles
          p.move(omega, @c1, @c2, @swarm_attractor)
        else
          p.move(alpha, c_n, @swarm_attractor)
        end
      end

      @generation += 1
    end
  end
end
