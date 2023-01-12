require 'concurrent'
require 'logger'

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

    DEFAULT_SWARM_SIZE = 20
    DEFAULT_NEXCESS = 3

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

      # http://vigir.missouri.edu/~gdesouza/Research/Conference_CDs/IEEE_WCCI_2020/CEC/Papers/E-24158.pdf
      @r_excl = 1.0

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

      # MPSO starts with a single swarm in 2008 paper
      # swarms = Array.new(@num_swarms) do |index|
      swarms = Array.new(@num_swarms) do |index|
        # initialize particle positions
        @init_pos = if @start_positions
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
        @init_vel = if @start_velocities
          # start velocities have the highest priority
          @start_velocities[index * @swarm_size / 2, @swarm_size / 2]
        elsif @random_velocity_func
          # random_velocity_func has the second highest priority
          Array.new(@swarm_size / 2) { @random_velocity_func.call }
        elsif @constraints
          # constraints were given, so we use them to initialize particle
          # velocities. to this end, we adopt the SPSO 2011 random velocity
          # initialization algorithm [CLERC12].
          @init_pos.map do |p|
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

        ChargedSwarm.new(size: @swarm_size, initial_positions: @init_pos,
          initial_velocities: @init_vel,
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

      overall_best = nil
      # calculate overall best
      swarm_attractors = swarms.map {|s| s.update_attractor }
      best_attractor = swarm_attractors.max_by {|x| x[:height] }

      if overall_best.nil?
        overall_best = best_attractor
      else
        overall_best = [ overall_best, best_attractor ].max_by {|x| x[:height] }
      end

      # puts "#{@search_space_extension}"
      average_space_extension = @search_space_extension.max # sum() / @search_space_extension.length.to_f
      # then try this one
      @r_excl = average_space_extension / (2 * @num_swarms)**(1.0 / @constraints.length)
      # default behavior is to loop forever
      begin
        @logger.debug "r_excl: #{@r_excl} @num_swarms: #{swarms.length}"
        iter += 1
        @logger.info "MultiSwarm QPSO - Starting iteration #{iter}" if @logger
        @logger.debug "Swarms: #{swarms.length}" if @logger

        # anti-convergence phase
        # this phase is necessary to ensure that a swarm is "spread" enough to
        # effectively follow the movements of a "peak" in the solution space.
        not_converged = 0
        worst_swarm = nil

        swarms.each do |swarm|
          swarm.particles.combination(2).each do |p1, p2|
            d_temp = 0
            p1.position.zip(p2.position).each do |x1, x2|
              d_temp += (x1 - x2) ** 2
            end
            d = Math::sqrt(d_temp)
            if d > 2 * @r_excl
              not_converged += 1
              worst_swarm = swarm if worst_swarm.nil? || (swarm.update_attractor[:height] < worst_swarm.update_attractor[:height])
              break
            end
          end
        end

        if not_converged == 0
          # add swarm if all have converge
          @logger.debug "All swarm converged #{swarms.length}"
          if swarms.length < @num_swarms # TODO FIX CONSTANT -- MAXIMUM NUMBER OF SWARM
            @logger.debug "Adding a new swarm"
            swarm = ChargedSwarm.new(size: @swarm_size, initial_positions: @init_pos,
              initial_velocities: @init_vel,
              constraints: @constraints, logger: @logger)
            swarm.each do |particle|
              # evaluate target function
              particle.evaluate(func)
            end
            swarm.update_attractor
            swarms << swarm
            @num_swarms += 1
          end
        elsif not_converged > DEFAULT_NEXCESS
          swarms.delete(worst_swarm)
          @logger&.debug "Number of active swarms: #{swarms.length}"
          @num_swarms -= 1
        end

        # update and evaluate the swarms
        swarms.each do |s|
          #puts "#{s.swarm_attractor}"
          bestval = func.call(s.swarm_attractor[:position]) 
          if bestval != s.bestfit
            @logger.info "> iter #{iter}, Detected change! Before best was #{s.bestfit}, now is #{bestval}"
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

        # print results
        if @logger && !@quiet
          @logger.info "> iter #{iter}, best: #{best_attractor[:position]}, #{best_attractor[:height]}" 
          #puts "> iter #{iter}, best: #{best_attractor[:position]}, #{best_attractor[:height]}" 
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

        reinit_swarms = []

        swarms.combination(2).each do |s1, s2|
          
          s1_best = s1.update_attractor
          s2_best = s2.update_attractor
          
          if s1_best && s2_best && !(reinit_swarms.include?(s1) || reinit_swarms.include?(s2))
            dist = 0

            s1_best[:position].zip(s2_best[:position]) do |x1, x2|
              dist += (x1 - x2)**2
              # puts "#{x1} #{x2}"
            end
            dist = Math::sqrt(dist)
            # puts "Swarm distance #{dist} #{@r_excl}"
            if dist < @r_excl
              @logger.debug "Swarm are colliding #{dist} #{@r_excl}"
              if s1_best[:height] <= s2_best[:height]
                reinit_swarms << s1
              else
                reinit_swarms << s2
              end
            else
              @logger.debug "Swarm are not colliding #{dist} #{@r_excl}"
            end
          end
      end

      reinit_swarms.each do |s|
        p_index = swarms.index(s)
        ChargedSwarm.new(size: @swarm_size, initial_positions: @init_pos,
          initial_velocities: @init_vel,
          constraints: @constraints, logger: @logger)
        s.each { |p| p.evaluate(func) }
        s.update_attractor
        swarms[p_index] = s
      end

      end while @exit_condition.nil? || !@exit_condition.call(iter, overall_best)

      overall_best
    end

  end

end
