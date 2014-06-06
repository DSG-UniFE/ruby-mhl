require 'matrix'
require 'securerandom'

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

      @generation = 1

      # define procedure to get dynamic value for alpha
      @get_alpha = if params.has_key? :alpha and params[:alpha].respond_to? :call
        params[:alpha]
      else
        ->(gen) { (params[:alpha] || DEFAULT_ALPHA).to_f }
      end
    end

    def mutate
      # get alpha parameter
      alpha = @get_alpha.call(@generation)

      # this calculates the C_n parameter (basically, the centroid of the set
      # of all the particle attractors) as defined in [SUN11], formulae 4.81
      # and 4.82
      c_n = @particles.inject(Vector[*[0]*@dimension]) {|s,p| s += p.attractor[:position] } / @size.to_f

      @particles.each { |p| p.move(alpha, c_n, @swarm_attractor) }

      @generation += 1
    end

  end
end
