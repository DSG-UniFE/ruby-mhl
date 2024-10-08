require 'erv'
require 'logger'
require 'concurrent'

# Grey Wolf Optimizer (GWO) is a population-based optimization algorithm
# that is inspired by the social hierarchy and hunting behavior of grey wolves.
# Seyedali Mirjalili, Seyed Mohammad Mirjalili, Andrew Lewis, Grey Wolf Optimizer,
# Advances in Engineering Software, Volume 69, March 2014, Pages 46-61.


module MHL
  class GreyWolfSolver 
    attr_reader :best_positions

    def initialize(opts)
      @population_size = opts[:population_size].to_i
      unless @population_size and @population_size.even?
        raise ArgumentError, 'Even population size required!'
      end

      @exit_condition   = opts[:exit_condition]
      # extract from the exit condition the number of iterations
      @max_iterations = opts[:iterations] || 100
      @start_population = opts[:start_population]
      # Initialize constraints
      @constraints = opts[:constraints]
      @dimensions = opts[:dimensions]
      @concurrent = nil
      @best_positions = []

      # A constraint is an array of two elements: [min, max]
      # @constraints is an array of constraints for each dimension of the search space 
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

    def initialize_poupulation
      # Initialize the population according to the constraints 
      population = []
      
      if @constraints
        @population_size.times do
          min = @constraints[:min]
          max = @constraints[:max]
          pi = []
          min.zip(max).map do |min_i, max_i|
            pi << min_i + rand * (max_i - min_i)
          end
          population << {position: pi}
        end
      else
        # no constraints are given here, therefore we assume that wolves 
        # are going to be initialized in the range [0, 1]
        @population_size.times do
          population << {position: Array.new(@dimensions) {rand}}
        end
      end
      population
    end

    # Implements the GWO algorithm and solve
    def solve(func, params={})

      if params[:concurrent]
        @concurrent = true
      else
        @concurrent = false
      end


      @logger.info('Starting GWO algorithm...') unless @quiet

      # Initialize the positions of the wolves
      positions = @start_population || initialize_poupulation 
      # Initialize the fitness of the wolves
      if @concurrent 
        futures = positions.each do |pos|
          Concurrent::Future.execute { func.call(pos[:position]) }
        end
        pos[:fitness] = futures.map(&:value)
      else
         positions.each do |pos|
           pos[:fitness] = func.call(pos[:position]) 
         end
      end
      
      iter_best = positions.min_by { |pos| pos[:fitness] }

      best_positions << iter_best[:fitness]

      iter = 0

      overall_best = iter_best

      # Main loop of the GWO algorithm
      begin

        #puts "positions: #{positions}"
        iter += 1
        # Update the positions of the wolves
        positions = update_positions(positions.map {|p| p[:position]}, positions.map {|p| p[:fitness]}, iter)
        # Update the fitness of the wolves
        if @concurrent
          futures = positions.map do |pos|
            Concurrent::Future.execute { func.call(pos[:position]) }
          end
          pos[:fitness] = futures.map(&:value)
        else
          positions.map do |pos| 
            pos[:fitness] = func.call(pos[:position]) 
          end
        end

        iter_best = positions.min_by { |pos| pos[:fitness] }

        if iter_best[:fitness] < overall_best[:fitness]
          overall_best = iter_best
        end


        # Update the best positions
        @best_positions << overall_best[:fitness]
        @logger.debug("Best fitness: #{iter_best}") unless @quiet

      end while @exit_condition.nil? || !@exit_condition.call(iter, overall_best)

      return overall_best, positions
    end

    def update_positions(positions, fitness, iteration)
      # get the alpha, beta, and delta wolves
      alpha, beta, delta = find_alpha_beta_delta(fitness)
      alpha = positions[alpha]
      beta = positions[beta]
      delta = positions[delta]

      #warn "alpha: #{alpha}, beta: #{beta}, delta: #{delta}"

      positions.map do |pos|
        new_positions = []
        # a is decreased during the iterations from 2 to 0
        # as in the grey wolf paper
        a = 2 - iteration * (2.0 / @max_iterations)
        @dimensions.times do |i|
          a1, c1 =  a * (2 * rand - 1), 2 * rand
          d_alpha = (c1 * alpha[i] - pos[i]).abs
          #warn "d_alpha: #{d_alpha}"
          x1 = alpha[i] - a1 * d_alpha

          a2, c2 = a * (2 * rand - 1), 2 * rand
          d_beta = (c2 * beta[i] - pos[i]).abs
          #warn "d_beta: #{d_beta}"
          x2 = beta[i] - a2 * d_beta

          a3, c3 = a * (2 * rand - 1), 2 * rand
          d_delta = (c3 * delta[i] - pos[i]).abs
          #warn "d_delta: #{d_delta}"
          x3 = delta[i] - a3 * d_delta
          new_positions[i] = (x1 + x2 + x3) / 3.0
          # clip the new position to the boundary of the search space 
          lb = @constraints[:min][i]
          ub = @constraints[:max][i]
          new_positions[i] = ub if new_positions[i] > ub
          new_positions[i] = lb if new_positions[i] < lb
        end
        { position: new_positions } 
      end
    end

    def find_alpha_beta_delta(fitness)
      alpha = fitness.index(fitness.min)
      beta = fitness.index(fitness.reject.with_index { |_, i| i == alpha }.min)
      delta = fitness.index(fitness.reject.with_index { |_, i| i == alpha || i == beta }.min)
      [alpha, beta, delta]
    end

    def distance(pos1, pos2)
      Math.sqrt(pos1.zip(pos2).map { |x, y| (x - y) ** 2 }.reduce(:+))
    end
  end
end
