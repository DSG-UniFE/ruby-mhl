require 'concurrent'
require 'logger'
require 'securerandom'

require 'mhl/charged_swarm'

module MHL
  # This solver implements the multiswarm QPSO algorithm, based on a number of
  # charged (QPSO Type 2) and neutral (PSO) swarms.
  # Filippo: this idea comes from the Blackwell et al. 2006 to extend what
  # was initially proposed in Blackwell et al. 2004
  # TODO: change the swarm type to QPSO2 (not using it at the moment)
  #
  # For more information, refer to:
  # [BLACKWELLBRANKE04] Tim Blackwell, Jürgen Branke, "Multi-swarm Optimization
  # in Dynamic Environments", Applications of Evolutionary Computing, pp.
  # 489-500, Springer, 2004. DOI: 10.1007/978-3-540-24653-4_50

  # but also to:

  # Blackwell, Tim, and Jürgen Branke. "Multiswarms, exclusion, and
  # anti-convergence in dynamic environments." IEEE transactions on
  # evolutionary computation 10.4 (2006): 459-472.

  # Blackwell, Branke, and Li, 2008, "Particle Swarms for Dynamic
  # Optimization Problems", which improved the first version of the algorithhm

  class MultiSwarmQPSOSolver
    attr_reader :best_positions

    DEFAULT_SWARM_SIZE = 20
    DEFAULT_NEXCESS = 3

    def initialize(opts = {})
      @swarm_size = (opts[:swarm_size] || DEFAULT_SWARM_SIZE).to_i

      @num_swarms = opts[:num_swarms].to_i
      raise ArgumentError, 'Number of swarms is a required parameter!' unless @num_swarms

      # store the maximum number of swarms as a fixed limit
      @max_swarms = @num_swarms

      @constraints = opts[:constraints]

      @random_position_func = opts[:random_position_func]
      @random_velocity_func = opts[:random_velocity_func]

      @start_positions  = opts[:start_positions]
      @start_velocities = opts[:start_velocities]

      @exit_condition = opts[:exit_condition]

      # http://vigir.missouri.edu/~gdesouza/Research/Conference_CDs/IEEE_WCCI_2020/CEC/Papers/E-24158.pdf
      @r_excl = 1.0

      @logger = case opts[:logger]
                when :stdout
                  Logger.new(STDOUT)
                when :stderr
                  Logger.new(STDERR)
                else
                  opts[:logger]
                end

      @quiet = opts[:quiet]

      @logger.level = opts[:log_level] if @logger && opts[:log_level]

      @best_positions = []
    end

    # This is the method that solves the optimization problem
    #
    # Parameter func is supposed to be a method (or a Proc, a lambda, or any callable
    # object) that accepts the genotype as argument (that is, the set of
    # parameters) and returns the phenotype (that is, the function result)
    def solve(func, _params = {})
      swarms = Array.new(@num_swarms) do |index|
        init_pos = generate_random_positions(index)
        init_vel = generate_random_velocities(init_pos, index)

        ChargedSwarm.new(size: @swarm_size, initial_positions: init_pos,
                         initial_velocities: init_vel,
                         constraints: @constraints, logger: @logger)
      end

      if @constraints
        @search_space_extension = []
        min = @constraints[:min]
        max = @constraints[:max]
        min.zip(max).each do |lb, ub|
          @search_space_extension << ub - lb
        end
      end

      # initialize variables
      iter = 0

      # evaluate each particle
      swarms.each do |swarm|
        swarm.each do |particle|
          # evaluate target function
          particle.evaluate(func)
        end
      end

      # calculate overall best
      swarm_attractors = swarms.map { |s| s.update_attractor }
      overall_best = swarm_attractors.max_by { |x| x[:height] }

      average_space_extension = @search_space_extension.max
      @dimension = @constraints[:min].length
      @r_excl = average_space_extension / ((2 * swarms.length)**(1.0 / @dimension))
      # default behavior is to loop forever
      begin
        @logger.debug "r_excl: #{@r_excl} @num_swarms: #{swarms.length}" if @logger
        iter += 1
        @logger.info "MultiSwarm QPSO - Starting iteration #{iter}" if @logger
        @logger.debug "Swarms: #{swarms.length}" if @logger

        # anti-convergence phase
        # this phase is necessary to ensure that a swarm is "spread" enough to
        # effectively follow the movements of a "peak" in the solution space.
        # A swarm is considered converged if its diameter (maximum distance
        # between any pair of particles) is less than 2 * r_excl.
        converged_swarms = []
        worst_swarm = nil

        swarms.each do |swarm|
          swarm_converged = true
          swarm.particles.combination(2).each do |p1, p2|
            d_temp = 0
            p1.position.zip(p2.position).each do |x1, x2|
              d_temp += (x1 - x2)**2
            end
            d = Math.sqrt(d_temp)
            if d > 2 * @r_excl
              swarm_converged = false
              break
            end
          end
          next unless swarm_converged

          converged_swarms << swarm
          if worst_swarm.nil? || (swarm.update_attractor[:height] < worst_swarm.update_attractor[:height])
            worst_swarm = swarm
          end
        end

        not_converged_count = swarms.length - converged_swarms.length

        if converged_swarms.length == swarms.length
          # all swarms have converged — add a new swarm if below the maximum
          @logger&.debug "All swarms converged (#{swarms.length} swarms)"
          if swarms.length < @max_swarms
            @logger&.debug 'Adding a new swarm'
            init_pos = generate_random_positions
            init_vel = generate_random_velocities(init_pos)
            new_swarm = ChargedSwarm.new(size: @swarm_size, initial_positions: init_pos,
                                         initial_velocities: init_vel,
                                         constraints: @constraints, logger: @logger)
            new_swarm.each do |particle|
              particle.evaluate(func)
            end
            new_swarm.update_attractor
            swarms << new_swarm
          end
        elsif not_converged_count > DEFAULT_NEXCESS && worst_swarm
          # too many non-converged swarms — remove the worst converged one
          swarms.delete(worst_swarm)
          @logger&.debug "Number of active swarms: #{swarms.length}"
        end

        # update and evaluate the swarms
        swarms.each do |s|
          bestval = func.call(s.swarm_attractor[:position])
          if bestval != s.bestfit
            @logger&.info "> iter #{iter}, Detected change! Before best was #{s.bestfit}, now is #{bestval}"
          end
          s.mutate
          s.each do |particle|
            # evaluate target function
            particle.evaluate(func)
          end
        end
        # update attractors (the highest particle in each swarm)

        swarm_attractors = swarms.map(&:update_attractor)
        best_attractor = swarm_attractors.max_by { |x| x[:height] }

        # calculate overall best
        overall_best = if overall_best.nil?
                         best_attractor
                       else
                         [overall_best, best_attractor].max_by { |x| x[:height] }
                       end

        # update best_positions
        @best_positions << overall_best[:height]

        # print results
        if @logger && !@quiet
          @logger.info "> iter #{iter}, best: #{best_attractor[:position]}, #{best_attractor[:height]}"
        end

        # exclusion phase
        # this phase is necessary to preserve diversity between swarms. we need
        # to ensure that swarm attractors are distant at least r_{excl} units
        # from each other. if the attractors of two swarms are closer than
        # r_{excl}, we randomly reinitialize the worst of those swarms.

        reinit_swarms = []

        swarms.combination(2).each do |s1, s2|
          s1_best = s1.update_attractor
          s2_best = s2.update_attractor

          next unless s1_best && s2_best && !(reinit_swarms.include?(s1) || reinit_swarms.include?(s2))

          dist = 0

          s1_best[:position].zip(s2_best[:position]).each do |x1, x2|
            dist += (x1 - x2)**2
          end
          dist = Math.sqrt(dist)
          if dist < @r_excl
            @logger&.debug "Swarms are colliding #{dist} #{@r_excl}"
            reinit_swarms << if s1_best[:height] <= s2_best[:height]
                               s1
                             else
                               s2
                             end
          else
            @logger&.debug "Swarms are not colliding #{dist} #{@r_excl}"
          end
        end

        reinit_swarms.each do |s|
          p_index = swarms.index(s)
          init_pos = generate_random_positions
          init_vel = generate_random_velocities(init_pos)
          new_swarm = ChargedSwarm.new(size: @swarm_size, initial_positions: init_pos,
                                       initial_velocities: init_vel,
                                       constraints: @constraints, logger: @logger)
          new_swarm.each { |p| p.evaluate(func) }
          new_swarm.update_attractor
          swarms[p_index] = new_swarm
        end

        # recalculate exclusion radius based on the current number of active swarms
        @r_excl = average_space_extension / ((2 * swarms.length)**(1.0 / @dimension))
      end while @exit_condition.nil? || !@exit_condition.call(iter, overall_best)

      overall_best
    end

    private

    # Generate random positions for a new swarm.
    # When index is provided, it's used to slice start_positions for the initial setup.
    def generate_random_positions(index = nil)
      if @start_positions && index
        @start_positions[index * @swarm_size, @swarm_size]
      elsif @random_position_func
        Array.new(@swarm_size) { @random_position_func.call }
      elsif @constraints
        # SPSO 2006-2011 random position initialization [CLERC12]
        Array.new(@swarm_size) do
          min = @constraints[:min]
          max = @constraints[:max]
          min.zip(max).map do |min_i, max_i|
            min_i + SecureRandom.random_number * (max_i - min_i)
          end
        end
      else
        raise ArgumentError, 'Not enough information to initialize particle positions!'
      end
    end

    # Generate random velocities for a new swarm.
    # When index is provided, it's used to slice start_velocities for the initial setup.
    def generate_random_velocities(positions, index = nil)
      if @start_velocities && index
        @start_velocities[index * @swarm_size, @swarm_size]
      elsif @random_velocity_func
        Array.new(@swarm_size) { @random_velocity_func.call }
      elsif @constraints
        # SPSO 2011 random velocity initialization [CLERC12]
        positions.map do |p|
          min = @constraints[:min]
          max = @constraints[:max]
          p.zip(min, max).map do |p_i, min_i, max_i|
            min_vel = min_i - p_i
            max_vel = max_i - p_i
            min_vel + SecureRandom.random_number * (max_vel - min_vel)
          end
        end
      else
        raise ArgumentError, 'Not enough information to initialize particle velocities!'
      end
    end
  end
end
