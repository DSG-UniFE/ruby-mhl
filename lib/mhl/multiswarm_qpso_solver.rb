require 'concurrent'
require 'logger'

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

    DEFAULT_SWARM_SIZE = 20

    def initialize(opts={})
      @swarm_size = opts[:swarm_size].try(:to_i) || DEFAULT_SWARM_SIZE

      @num_swarms = opts[:num_swarms].to_i
      unless @num_swarms
        raise ArgumentError, 'Number of swarms is a required parameter!'
      end

      @constraints = opts[:constraints]

      @random_position_func = opts[:random_position_func]
      @random_velocity_func = opts[:random_velocity_func]

      @start_positions  = opts[:start_positions]
      @start_velocities = opts[:start_velocities]

      @exit_condition = opts[:exit_condition]

      case opts[:logger]
      when :stdout
        @logger = Logger.new(STDOUT)
      when :stderr
        @logger = Logger.new(STDERR)
      else
        @logger = opts[:logger]
      end

      @quiet = opts[:quiet]

      if @logger && opts[:log_level]
        @logger.level = opts[:log_level]
      end
    end

    # This is the method that solves the optimization problem
    #
    # Parameter func is supposed to be a method (or a Proc, a lambda, or any callable
    # object) that accepts the genotype as argument (that is, the set of
    # parameters) and returns the phenotype (that is, the function result)
    def solve(func, params={})

      swarms = Array.new(@num_swarms) do |index|
        # initialize particle positions
        init_pos = if @start_positions
          # start positions have the highest priority
          @start_positions[index * @swarm_size, @swarm_size]
        elsif @random_position_func
          # random_position_func has the second highest priority
          Array.new(@swarm_size) { @random_position_func.call }
        elsif @constraints
          # constraints were given, so we use them to initialize particle
          # positions. to this end, we adopt the SPSO 2006-2011 random position
          # initialization algorithm [CLERC12].
          Array.new(@swarm_size) do
            min = @constraints[:min]
            max = @constraints[:max]
            # randomization is independent along each dimension
            min.zip(max).map do |min_i,max_i|
              min_i + SecureRandom.random_number * (max_i - min_i)
            end
          end
        else
          raise ArgumentError, "Not enough information to initialize particle positions!"
        end

        # initialize particle velocities
        init_vel = if @start_velocities
          # start velocities have the highest priority
          @start_velocities[index * @swarm_size / 2, @swarm_size / 2]
        elsif @random_velocity_func
          # random_velocity_func has the second highest priority
          Array.new(@swarm_size / 2) { @random_velocity_func.call }
        elsif @constraints
          # constraints were given, so we use them to initialize particle
          # velocities. to this end, we adopt the SPSO 2011 random velocity
          # initialization algorithm [CLERC12].
          init_pos.map do |p|
            min = @constraints[:min]
            max = @constraints[:max]
            # randomization is independent along each dimension
            p.zip(min,max).map do |p_i,min_i,max_i|
              min_vel = min_i - p_i
              max_vel = max_i - p_i
              min_vel + SecureRandom.random_number * (max_vel - min_vel)
            end
          end
        else
          raise ArgumentError, "Not enough information to initialize particle velocities!"
        end

        ChargedSwarm.new(size: @swarm_size, initial_positions: init_pos,
                         initial_velocities: init_vel,
                         constraints: @constraints, logger: @logger)
      end

      # initialize variables
      iter = 0
      overall_best = nil

      # default behavior is to loop forever
      begin
        iter += 1
        @logger.info "MultiSwarm QPSO - Starting iteration #{iter}" if @logger

        # assess height for every particle
        if params[:concurrent]
          # the function to optimize is thread safe: call it multiple times in
          # a concurrent fashion
          # to this end, we use the high level promise-based construct
          # recommended by the authors of ruby's (fantastic) concurrent gem
          promises = swarms.map do |swarm|
            swarm.map do |particle|
              Concurrent::Promise.execute do
                # evaluate target function
                particle.evaluate(func)
              end
            end
          end.flatten!

          # wait for all the spawned threads to finish
          promises.map(&:wait)
        else
          # the function to optimize is not thread safe: call it multiple times
          # in a sequential fashion
          swarms.each do |swarm|
            swarm.each do |particle|
              # evaluate target function
              particle.evaluate(func)
            end
          end
        end

        # update attractors (the highest particle in each swarm)
        swarm_attractors = swarms.map {|s| s.update_attractor }

        best_attractor = swarm_attractors.max_by {|x| x[:height] }

        # print results
        if @logger and !@quiet
          @logger.info "> iter #{iter}, best: #{best_attractor[:position]}, #{best_attractor[:height]}" 
        end

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

      end while @exit_condition.nil? or !@exit_condition.call(iter, overall_best)

      overall_best
    end

  end

end
