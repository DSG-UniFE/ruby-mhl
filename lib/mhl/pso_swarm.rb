require 'matrix'
require 'securerandom'

require 'mhl/generic_swarm'
require 'mhl/particle'


module MHL
  class PSOSwarm < GenericSwarmBehavior

    def initialize(size, initial_positions, initial_velocities, params={})
      @size      = size
      @particles = Array.new(@size) do |index|
        Particle.new(initial_positions[index], initial_velocities[index])
      end

      @generation = 1

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

    def mutate(params={})
      # get omega parameter
      omega = @get_omega.call(@generation)

      # move particles
      @particles.each { |p| p.move(omega, @c1, @c2, @swarm_attractor) }

      @generation += 1
    end
  end
end
