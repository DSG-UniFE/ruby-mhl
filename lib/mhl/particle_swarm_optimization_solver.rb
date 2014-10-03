require 'concurrent'
require 'facter'
require 'logger'

require 'mhl/pso_swarm'


module MHL

  # This solver implements the PSO with inertia weight variant algorithm.
  #
  # For more information, refer to equation 4 of:
  # [REZAEEJORDEHI13] A. Rezaee Jordehi & J. Jasni (2013) Parameter selection
  # in particle swarm optimisation: a survey, Journal of Experimental &
  # Theoretical Artificial Intelligence, 25:4, pp. 527-542, DOI:
  # 10.1080/0952813X.2013.782348
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

      @pool = Concurrent::FixedThreadPool.new(Facter.value(:processorcount).to_i * 4)

      case opts[:logger]
      when :stdout
        @logger = Logger.new(STDOUT)
      when :stderr
        @logger = Logger.new(STDERR)
      else
        @logger = opts[:logger]
      end

      @quiet = opts[:quiet]

      if @logger
        @logger.level = (opts[:log_level] or Logger::WARN)
      end
    end

    # This is the method that solves the optimization problem
    #
    # Parameter func is supposed to be a method (or a Proc, a lambda, or any callable
    # object) that accepts the genotype as argument (that is, the set of
    # parameters) and returns the phenotype (that is, the function result)
    def solve(func, params={})
      # setup particles
      if @start_positions.nil?
        swarm = PSOSwarm.new(@swarm_size,
                             Array.new(@swarm_size) { Vector[*@random_position_func.call] },
                             Array.new(@swarm_size) { Vector[*@random_velocity_func.call] },
                             params)
      else
        raise 'Unimplemented yet!'
        # particles = @start_positions.each_slice(2).map do |pos,vel|
        #   { position: Vector[*pos], velocity: Vector[*vel] }
        # end
      end

      # initialize variables
      gen = 0
      overall_best = nil

      # default behavior is to loop forever
      begin
        gen += 1
        @logger.info("PSO - Starting generation #{gen}") if @logger

        # create latch to control program termination
        latch = Concurrent::CountDownLatch.new(@swarm_size)

        # assess height for every particle
        swarm.each do |particle|
          @pool.post do
            # evaluate target function
            particle.evaluate(func)
            # update latch
            latch.count_down
          end
        end

        # wait for all the threads to terminate
        latch.wait

        # get swarm attractor (the highest particle)
        swarm_attractor = swarm.update_attractor

        # print results
        puts "> gen #{gen}, best: #{swarm_attractor[:position]}, #{swarm_attractor[:height]}" unless @quiet

        # calculate overall best (that plays the role of swarm attractor)
        if overall_best.nil?
          overall_best = swarm_attractor
        else
          overall_best = [ overall_best, swarm_attractor ].max_by {|x| x[:height] }
        end

        # mutate swarm
        swarm.mutate

      end while @exit_condition.nil? or !@exit_condition.call(gen, overall_best)

      overall_best
    end

  end

end
