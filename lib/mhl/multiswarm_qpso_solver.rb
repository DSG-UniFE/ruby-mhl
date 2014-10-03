require 'concurrent'
require 'facter'
require 'logger'
require 'matrix'

require 'mhl/charged_swarm'


module MHL
  # This solver implements the multiswarm QPSO algorithm, based on a number of
  # charged (QPSO Type 2) and neutral (PSO) swarms.
  #
  # For more information, refer to:
  # [BLACKWELLBRANKE04] Tim Blackwell, Jürgen Branke, "Multi-swarm Optimization
  # in Dynamic Environments", Applications of Evolutionary Computing, pp.
  # 489-500, Springer, 2004. DOI: 10.1007/978-3-540-24653-4_50
  class MultiSwarmQPSOSolver

    def initialize(opts={})
      @swarm_size = opts[:swarm_size].to_i
      unless @swarm_size
        raise ArgumentError, 'Swarm size is a required parameter!'
      end

      @num_swarms = opts[:num_swarms].to_i
      unless @num_swarms
        raise ArgumentError, 'Number of swarms is a required parameter!'
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
        @logger.level = opts[:log_level] or Logger::WARN
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
        swarms = Array.new(@num_swarms) do |index|
          ChargedSwarm.new(@swarm_size,
                           Array.new(@swarm_size)     { Vector[*@random_position_func.call] },
                           Array.new(@swarm_size / 2) { Vector[*@random_velocity_func.call] },
                           params)
        end
      else
        raise 'Unimplemented yet!'
        # particles = @start_positions.each_slice(2).map do |pos,vel|
        #   { position: Vector[*pos] }
        # end
      end

      # initialize variables
      gen = 0
      overall_best = nil

      # default behavior is to loop forever
      begin
        gen += 1
        @logger.info "MSQPSO - Starting generation #{gen}" if @logger

        # create latch to control program termination
        latch = Concurrent::CountDownLatch.new(@num_swarms * @swarm_size)

        # assess height for every particle
        swarms.each do |s|
          s.each do |particle|
            @pool.post do
              # evaluate target function
              particle.evaluate(func)
              # update latch
              latch.count_down
            end
          end
        end

        # wait for all the evaluations to end
        latch.wait

        # update attractors (the highest particle in each swarm)
        swarm_attractors = swarms.map {|s| s.update_attractor }

        best_attractor = swarm_attractors.max_by {|x| x[:height] }

        # print results
        puts "> gen #{gen}, best: #{best_attractor[:position]}, #{best_attractor[:height]}" unless @quiet

        # calculate overall best
        if overall_best.nil?
          overall_best = best_attractor
        else
          overall_best = [ overall_best, best_attractor ].max_by {|x| x[:height] }
        end

        # exclusion phase
        # this phase is necessary to preserve diversity between swarms. we need
        # to ensure that swarm attractors are distant at least r_{excl} units
        # from each other. if the attractors of two swarms are closer than
        # r_{excl}, we randomly reinitialize the worst of those swarms.
        # TODO: IMPLEMENT

        # anti-convergence phase
        # this phase is necessary to ensure that a swarm is "spread" enough to
        # effectively follow the movements of a "peak" in the solution space.
        # TODO: IMPLEMENT

        # mutate swarms
        swarms.each {|s| s.mutate }

      end while @exit_condition.nil? or !@exit_condition.call(gen, overall_best)

      overall_best
    end

  end

end
