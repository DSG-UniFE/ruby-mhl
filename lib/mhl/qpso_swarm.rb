require 'mhl/generic_swarm'
require 'mhl/quantum_particle'


module MHL
  class QPSOSwarm < GenericSwarmBehavior

    def initialize(size, initial_positions, params={})
      @size      = size
      @particles = Array.new(@size) do |index|
        QuantumParticle.new(initial_positions[index])
      end

      # find problem dimension
      @dimension  = initial_positions[0].size

      @iteration = 1

      # define procedure to get dynamic value for alpha
      @get_alpha = if params.has_key? :alpha and params[:alpha].respond_to? :call
        params[:alpha]
      else
        ->(it) { (params[:alpha] || DEFAULT_ALPHA).to_f }
      end

      if params.has_key? :constraints
        puts "QPSOSwarm called w/ constraints: #{params[:constraints]}"
      end

      @constraints = params[:constraints]
    end

    def mutate
      # get alpha parameter
      alpha = @get_alpha.call(@iteration)

      # this calculates the C_n parameter (the centroid of the set of all the
      # particle attractors) as defined in equations 4.81 and 4.82 of [SUN11].
      attractors = @particles.map {|p| p.attractor[:position] }
      c_n = 0.upto(@dimension-1).map do |j|
        attractors.inject(0.0) {|s,attr| s += attr[j] } / @size.to_f
      end

      # move particles
      @particles.each do |p|
        p.move(alpha, c_n, @swarm_attractor)
        if @constraints
          p.remain_within(@constraints)
        end
      end

      @iteration += 1
    end

  end
end
