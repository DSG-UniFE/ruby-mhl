require 'concurrent'
require 'facter'
require 'logger'
require 'matrix'
require 'securerandom'

module MHL

  class ParticleSwarmOptimizationSolver

    def initialize(opts={})
      @swarm_size = opts[:swarm_size].to_i
      unless @swarm_size
        raise ArgumentError, 'Swarm size is a required parameter!'
      end

      @random_position_func = opts[:random_position_func]
      @random_velocity_func = opts[:random_velocity_func]

      @start_positions = opts[:start_positions]
      @exit_condition  = opts[:exit_condition]

      @pool = Concurrent::FixedThreadPool.new(Facter.processorcount.to_i * 4)

      case opts[:logger]
      when :stdout
        @logger = Logger.new(STDOUT)
      else
        @logger = opts[:logger]
      end

      if @logger
        @logger.level = opts[:log_level] or Logger::WARN
      end
    end

    # This is the method that solves the optimization problem
    #
    # Parameter func is supposed to be a method (or a Proc, a lambda, or any callable
    # object) that accepts the genotype as argument (that is, the set of
    # parameters) and returns the phenotype (that is, the function result)
    def solve(func)
      # setup particles
      if @start_positions.nil?
        particles = Array.new(@swarm_size) do
          { position: Vector[*@random_position_func.call], velocity: Vector[*@random_velocity_func.call] }
        end
      else
        particles = @start_positions.each_slice(2).map do |pos,vel|
          { position: Vector[*pos], velocity: Vector[*vel] }
        end
      end

      # initialize variables
      gen = 0
      overall_best = nil

      # completely made up values
      alpha   = 0.5
      beta    = 0.3
      gamma   = 0.7
      delta   = 0.5
      epsilon = 0.6

      swarm_mutex = Mutex.new

      # default behavior is to loop forever
      begin
        gen += 1
        @logger.info "PSO - Starting generation #{gen}" if @logger

        # create latch to control program termination
        latch = Concurrent::CountDownLatch.new(@swarm_size)

        # assess height for every particle
        particles.each do |p|
          @pool.post do
            # do we need to syncronize this call through swarm_mutex?
            # probably not.
            ret = func.call(p[:position])

            # protect write access to particles struct using swarm_mutex
            swarm_mutex.synchronize do
              p[:height] = ret
            end

            # update latch
            latch.count_down
          end
        end

        # wait for all the threads to terminate
        latch.wait

        # wait for all the evaluations to end
        particles.each_with_index do |p,i|
          if p[:highest_value].nil? or p[:height] > p[:highest_value]
            p[:highest_value]    = p[:height]
            p[:highest_position] = p[:position]
          end
        end

        # find highest particle
        highest_particle = particles.max_by {|x| x[:height] }

        # calculate overall best
        if overall_best.nil?
          overall_best = highest_particle
        else
          overall_best = [ overall_best, highest_particle ].max_by {|x| x[:height] }
        end

        # mutate swarm
        particles.each do |p|
          # randomly sample particles and use them as informants
          informants = random_portion(particles)

          # make sure that p is included among the informants
          informants << p unless informants.include? p

          # get fittest informant
          fittest_informant = informants.max_by {|x| x[:height] }

          # update velocity
          p[:velocity] =
            alpha * p[:velocity] +
            beta  * (p[:highest_position] - p[:position]) +
            gamma * (fittest_informant[:highest_position] - p[:position]) +
            delta * (overall_best[:highest_position] - p[:position])

          # update position
          p[:position] = p[:position] + epsilon * p[:velocity]
        end

      end while @exit_condition.nil? or !@exit_condition.call(gen, overall_best)
    end

    private

      def random_portion(array, ratio=0.1)
        # get size of random array to return
        size = (ratio * array.size).ceil

        (1..size).inject([]) do |acc,i|
          # randomly sample a new element
          begin
            new_element = array[SecureRandom.random_number(array.size)]
          end while acc.include? new_element

          # insert element in the accumulator
          acc << new_element
        end
      end

  end

end
