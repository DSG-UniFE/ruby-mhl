require 'concurrent'
require 'facter'
require 'logger'
require 'matrix'
require 'securerandom'

module MHL

  # This solver implements the QPSO Type 2 algorithm.
  #
  # For more information, refer to equation 4.82 of:
  # [SUN11] Jun Sun, Choi-Hong Lai, Xiao-Jun Wu, "Particle Swarm Optimisation:
  # Classical and Quantum Perspectives", CRC Press, 2011
  class QuantumPSOSolver

    # According to [SUN11], this looks like a sensible default parameter
    DEFAULT_ALPHA = 0.75 # \alpha is the inertia weight

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
      # setup particles
      if @start_positions.nil?
        particles = Array.new(@swarm_size) do
          { position: Vector[*@random_position_func.call] }
        end
      else
        particles = @start_positions.map do |pos|
          { position: Vector[*pos] }
        end
      end

      # find problem dimension
      n = particles[0][:position].size

      # initialize variables
      gen = 0
      overall_best = nil

      # define procedure to get dynamic value for alpha
      get_alpha = if params.has_key? :alpha and params[:alpha].respond_to? :call
        params[:alpha]
      else
        ->(gen) { params[:alpha] || DEFAULT_ALPHA }
      end

      swarm_mutex = Mutex.new

      # default behavior is to loop forever
      begin
        gen += 1
        @logger.info "QPSO - Starting generation #{gen}" if @logger

        # get inertia weight
        alpha = get_alpha.call(gen)

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

        # wait for all the evaluations to end
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

        # mean_best represents the C_n parameter in [SUN11], formula 4.82
        mean_best = particles.inject(Vector[*[0]*n]) {|s,x| s += x[:position] } / particles.size.to_f

        # mutate swarm
        particles.each_with_index do |p,i|
          # phi represents the \phi_{i,n} parameter in [SUN11], formula 4.83
          phi = Array.new(n) { SecureRandom.random_number }

          # p_i represents the p_{i,n} parameter in [SUN11], formulae 4.82 and 4.83
          p_i =
            Vector[*phi.zip(p[:highest_position]).map {|phi_j,p_j| phi_j * p_j }] +
            Vector[*phi.zip(overall_best[:position]).map {|phi_j,g_j| (1.0 - phi_j) * g_j }]

          # delta represents the displacement for the current position.
          # See [SUN11], formula 4.82
          delta =
            p[:position].zip(mean_best).map {|x,y| alpha * (x-y).abs }. # \alpha * | X_{i,n} - C_n |
            map {|x| x * Math.log(1.0 / SecureRandom.random_number) }   # log(\frac{1}{u_{i,n+1}})

          # update position
          if SecureRandom.random_number < 0.5
            p[:position] = p_i + Vector[*delta]
          else
            p[:position] = p_i - Vector[*delta]
          end

        end

      end while @exit_condition.nil? or !@exit_condition.call(gen, overall_best)

      overall_best
    end

  end

end
