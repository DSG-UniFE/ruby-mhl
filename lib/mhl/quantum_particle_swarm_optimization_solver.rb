require 'concurrent'
require 'logger'
require 'securerandom'

require 'mhl/qpso_swarm'


module MHL

  # This solver implements the QPSO Type 2 algorithm.
  #
  # For more information, refer to equation 4.82 of:
  # [SUN11] Jun Sun, Choi-Hong Lai, Xiao-Jun Wu, "Particle Swarm Optimisation:
  # Classical and Quantum Perspectives", CRC Press, 2011
  class QuantumPSOSolver

    DEFAULT_SWARM_SIZE = 40

    def initialize(opts={})
      @swarm_size = opts[:swarm_size].try(:to_i) || DEFAULT_SWARM_SIZE

      @constraints = opts[:constraints]

      @random_position_func = opts[:random_position_func]

      @start_positions = opts[:start_positions]

      @exit_condition  = opts[:exit_condition]

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
      # initialize particle positions
      init_pos = if @start_positions
        # start positions have the highest priority
        @start_positions
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
          random_pos = min.zip(max).map do |min_i,max_i|
            min_i + SecureRandom.random_number * (max_i - min_i)
          end
        end
      else
        raise ArgumentError, "Not enough information to initialize particle positions!"
      end

      swarm = QPSOSwarm.new(@swarm_size, init_pos,
                            params.merge(constraints: @constraints))

      # initialize variables
      iter = 0
      overall_best = nil

      # default behavior is to loop forever
      begin
        iter += 1
        @logger.info "QPSO - Starting iteration #{iter}" if @logger

        if params[:concurrent]
          # the function to optimize is thread safe: call it multiple times in
          # a concurrent fashion
          # to this end, we use the high level promise-based construct
          # recommended by the authors of ruby's (fantastic) concurrent gem
          promises = swarm.map do |particle|
            Concurrent::Promise.execute do
              # evaluate target function
              particle.evaluate(func)
            end
          end

          # wait for all the spawned threads to finish
          promises.map(&:wait)
        else
          # the function to optimize is not thread safe: call it multiple times
          # in a sequential fashion
          swarm.each do |particle|
            # evaluate target function
            particle.evaluate(func)
          end
        end

        # get swarm attractor (the highest particle)
        swarm_attractor = swarm.update_attractor

        # print results
        puts "> iter #{iter}, best: #{swarm_attractor[:position]}, #{swarm_attractor[:height]}" unless @quiet

        # calculate overall best (that plays the role of swarm attractor)
        if overall_best.nil?
          overall_best = swarm_attractor
        else
          overall_best = [ overall_best, swarm_attractor ].max_by {|x| x[:height] }
        end

        # mutate swarm
        swarm.mutate

      end while @exit_condition.nil? or !@exit_condition.call(iter, overall_best)

      overall_best
    end

  end

end
