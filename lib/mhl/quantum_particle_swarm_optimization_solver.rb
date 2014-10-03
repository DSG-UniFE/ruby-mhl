require 'concurrent'
require 'facter'
require 'logger'
require 'matrix'
require 'securerandom'

require 'mhl/qpso_swarm'


module MHL

  # This solver implements the QPSO Type 2 algorithm.
  #
  # For more information, refer to equation 4.82 of:
  # [SUN11] Jun Sun, Choi-Hong Lai, Xiao-Jun Wu, "Particle Swarm Optimisation:
  # Classical and Quantum Perspectives", CRC Press, 2011
  class QuantumPSOSolver

    def initialize(opts={})
      @swarm_size = opts[:swarm_size].to_i
      unless @swarm_size
        raise ArgumentError, 'Swarm size is a required parameter!'
      end

      @random_position_func = opts[:random_position_func]

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
      # setup swarm
      if @start_positions.nil?
        swarm = QPSOSwarm.new(@swarm_size,
                              Array.new(@swarm_size) { Vector[*@random_position_func.call] },
                              params)
      else
        raise 'Unimplemented yet!'
        # particles = @start_positions.map do |pos|
        #   { position: Vector[*pos] }
        # end
      end

      # initialize variables
      gen = 0
      overall_best = nil

      # default behavior is to loop forever
      begin
        gen += 1
        @logger.info "QPSO - Starting generation #{gen}" if @logger

        # create latch to control program termination
        latch = Concurrent::CountDownLatch.new(@swarm_size)

        swarm.each do |particle|
          @pool.post do
            # evaluate target function
            particle.evaluate(func)
            # update latch
            latch.count_down
          end
        end

        # wait for all the evaluations to end
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
