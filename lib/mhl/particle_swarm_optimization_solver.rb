require 'concurrent'
require 'facter'
require 'logger'
require 'matrix'
require 'securerandom'

module MHL

  # This solver implements the PSO with inertia weight variant algorithm.
  #
  # For more information, refer to equation 4 of:
  # [REZAEEJORDEHI13] A. Rezaee Jordehi & J. Jasni (2013) Parameter selection
  # in particle swarm optimisation: a survey, Journal of Experimental &
  # Theoretical Artificial Intelligence, 25:4, pp. 527-542, DOI:
  # 10.1080/0952813X.2013.782348
  class ParticleSwarmOptimizationSolver

    # The following values were taken from:
    # [BLACKWELLBRANKE04] Tim Blackwell, Jürgen Branke, "Multi-swarm
    # Optimization in Dynamic Environments", Applications of Evolutionary
    # Computing Lecture Notes in Computer Science Volume 3005, 2004, pp. 489-500,
    # DOI: 10.1007/978-3-540-24653-4_50
    DEFAULT_OMEGA = 0.729843788 # \omega is the inertia weight
    DEFAULT_C1    = 2.05 * DEFAULT_OMEGA # C_1 is the cognitive acceleration coefficient
    DEFAULT_C2    = 2.05 * DEFAULT_OMEGA # C_2 is the social acceleration coefficient

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

      # define procedure to get dynamic value for omega
      get_omega = if params.has_key? :omega and params[:omega].respond_to? :call
        params[:omega]
      else
        ->(gen) { params[:omega] || DEFAULT_OMEGA }
      end

      # get values for parameters C1 and C2
      c1 = params[:c1] || DEFAULT_C1
      c2 = params[:c1] || DEFAULT_C2

      swarm_mutex = Mutex.new

      # default behavior is to loop forever
      begin
        gen += 1
        @logger.info("PSO - Starting generation #{gen}") if @logger

        # get inertia weight
        omega = get_omega.call(gen)

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

        # update particle attractors (i.e., the best position it encountered so far)
        particles.each do |p|
          if p[:highest_value].nil? or p[:height] > p[:highest_value]
            p[:highest_value]    = p[:height]
            p[:highest_position] = p[:position]
          end
        end

        # get highest particle
        highest_particle = particles.max_by {|x| x[:height] }

        # calculate overall best (that plays the role of swarm attractor)
        if overall_best.nil?
          overall_best = highest_particle
        else
          overall_best = [ overall_best, highest_particle ].max_by {|x| x[:height] }
        end

        # print results
        puts "> gen #{gen}, best: #{overall_best[:position]}, #{overall_best[:height]}" unless @quiet

        # mutate swarm
        particles.each do |p|
          # update velocity
          p[:velocity] =
            # previous velocity is damped by inertia weight
            omega * p[:velocity] +
            # "memory" component (linear attraction towards the best position
            # that this particle encountered so far)
            c1 * SecureRandom.random_number * (p[:highest_position] - p[:position]) +
            # "social" component (linear attraction towards the best position
            # that the entire swarm encountered so far)
            c2 * SecureRandom.random_number * (overall_best[:position] - p[:position])

          # update position
          p[:position] = p[:position] + p[:velocity]
        end

      end while @exit_condition.nil? or !@exit_condition.call(gen, overall_best)

      overall_best
    end

  end

end
