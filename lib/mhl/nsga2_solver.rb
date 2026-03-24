require 'concurrent'
require 'logger'
require 'securerandom'

require 'mhl/dominance_utils'

module MHL
  # This solver implements the NSGA-II (Non-dominated Sorting Genetic
  # Algorithm II) multi-objective optimization algorithm, as described in
  # [DEB02]:
  #   K. Deb, A. Pratap, S. Agarwal, T. Meyarivan, "A Fast and Elitist
  #   Multiobjective Genetic Algorithm: NSGA-II", IEEE Transactions on
  #   Evolutionary Computation, Vol. 6, No. 2, April 2002.
  #
  # NSGA-II uses non-dominated sorting and crowding distance to maintain
  # a well-spread Pareto front approximation. It employs Simulated Binary
  # Crossover (SBX) and polynomial mutation as genetic operators.
  #
  # All objectives are minimized. If you need to maximize an objective,
  # negate it in the objective function.
  class NSGA2Solver
    attr_reader :best_positions

    DEFAULT_POPULATION_SIZE = 40

    # SBX crossover distribution index [DEB02]
    DEFAULT_ETA_C = 20.0

    # Polynomial mutation distribution index [DEB02]
    DEFAULT_ETA_M = 20.0

    # Default crossover probability
    DEFAULT_CROSSOVER_PROBABILITY = 0.9

    # Default mutation probability (typically 1/n, set in initialize)
    DEFAULT_MUTATION_PROBABILITY = nil

    def initialize(opts = {})
      @population_size = (opts[:population_size] || DEFAULT_POPULATION_SIZE).to_i
      raise ArgumentError, 'Even population size required!' unless @population_size and @population_size.even?

      @constraints = opts[:constraints]
      unless @constraints and @constraints[:min] and @constraints[:max]
        raise ArgumentError, 'Constraints with :min and :max arrays are required!'
      end

      @dimensions = @constraints[:min].size
      unless @constraints[:max].size == @dimensions
        raise ArgumentError, 'Constraints :min and :max must have the same dimension!'
      end

      @num_objectives = opts[:num_objectives].to_i
      raise ArgumentError, 'Number of objectives must be at least 2!' unless @num_objectives and @num_objectives >= 2

      @eta_c = (opts[:eta_c] || DEFAULT_ETA_C).to_f
      @eta_m = (opts[:eta_m] || DEFAULT_ETA_M).to_f
      @crossover_probability = (opts[:crossover_probability] || DEFAULT_CROSSOVER_PROBABILITY).to_f
      @mutation_probability = (opts[:mutation_probability] || 1.0 / @dimensions).to_f

      @start_population = opts[:start_population]
      @random_position_func = opts[:random_position_func]

      @exit_condition = opts[:exit_condition]

      @logger = case opts[:logger]
                when :stdout
                  Logger.new(STDOUT)
                when :stderr
                  Logger.new(STDERR)
                else
                  opts[:logger]
                end

      @quiet = opts[:quiet]

      return unless @logger && opts[:log_level]

      @logger.level = opts[:log_level]

      @best_positions = []
    end

    # This is the method that solves the multi-objective optimization problem
    #
    # Parameter func is supposed to be a method (or a Proc, a lambda, or any
    # callable object) that accepts a solution vector as argument and returns
    # an array of objective values. All objectives are minimized.
    #
    # Returns an array of non-dominated solutions from the final population,
    # each represented as { variables: [...], objectives: [...] }.
    def solve(func, params = {})
      # initialize population
      population = initialize_population

      # initialize variables
      gen = 0

      # default behavior is to loop forever
      begin
        gen += 1
        @logger.info("NSGA-II - Starting generation #{gen}") if @logger

        # evaluate population
        evaluate_population(population, func, params[:concurrent])

        if gen == 1
          # for the first generation, just do non-dominated sorting and
          # crowding distance assignment on the initial population
          fronts = DominanceUtils.fast_non_dominated_sort(population)
          assign_rank_and_crowding(population, fronts)
        end

        # create offspring via selection, crossover, and mutation
        offspring = make_offspring(population)

        # evaluate offspring
        evaluate_population(offspring, func, params[:concurrent])

        # combine parent and offspring populations
        combined = population + offspring

        # perform non-dominated sorting on the combined population
        fronts = DominanceUtils.fast_non_dominated_sort(combined)

        # select next generation from combined population
        population = select_next_generation(combined, fronts)

        # track the number of solutions in the first Pareto front
        pareto_front = population.select { |ind| ind[:rank] == 0 }
        @best_positions << pareto_front.size

        # print results
        @logger.info "> gen #{gen}, pareto front size: #{pareto_front.size}" if @logger and !@quiet
      end while @exit_condition.nil? or !@exit_condition.call(gen, pareto_front)

      # return the first Pareto front
      pareto_front.map do |ind|
        { variables: ind[:variables].dup, objectives: ind[:objectives].dup }
      end
    end

    private

    def initialize_population
      positions = if @start_population
                    @start_population
                  elsif @random_position_func
                    Array.new(@population_size) { @random_position_func.call }
                  else
                    # initialize using constraints, similar to SPSO 2006-2011
                    # random initialization [CLERC12]
                    min = @constraints[:min]
                    max = @constraints[:max]
                    Array.new(@population_size) do
                      min.zip(max).map do |min_i, max_i|
                        min_i + SecureRandom.random_number * (max_i - min_i)
                      end
                    end
                  end

      positions.map { |pos| { variables: pos } }
    end

    def evaluate_population(population, func, concurrent)
      if concurrent
        # the function to optimize is thread safe: call it multiple times in
        # a concurrent fashion
        # to this end, we use the high level promise-based construct
        # recommended by the authors of ruby's (fantastic) concurrent gem
        promises = population.map do |member|
          Concurrent::Promise.execute do
            member[:objectives] = func.call(member[:variables]) unless member[:objectives]
          end
        end

        # wait for all the spawned threads to finish
        promises.map(&:wait)
      else
        # the function to optimize is not thread safe: call it multiple times
        # in a sequential fashion
        population.each do |member|
          member[:objectives] = func.call(member[:variables]) unless member[:objectives]
        end
      end
    end

    def assign_rank_and_crowding(population, fronts)
      fronts.each_with_index do |front, rank|
        distances = DominanceUtils.crowding_distance_assignment(front, population)
        front.each do |i|
          population[i][:rank] = rank
          population[i][:crowding_distance] = distances[i]
        end
      end
    end

    def select_next_generation(combined, fronts)
      next_population = []

      fronts.each_with_index do |front, rank|
        distances = DominanceUtils.crowding_distance_assignment(front, combined)
        front.each do |i|
          combined[i][:rank] = rank
          combined[i][:crowding_distance] = distances[i]
        end

        if next_population.size + front.size <= @population_size
          # the entire front fits
          front.each { |i| next_population << combined[i] }
        else
          # this front needs to be truncated using crowding distance
          remaining = @population_size - next_population.size
          sorted = front.sort_by { |i| -combined[i][:crowding_distance] }
          sorted.first(remaining).each { |i| next_population << combined[i] }
          break
        end
      end

      next_population
    end

    def make_offspring(population)
      offspring = []

      while offspring.size < @population_size
        # binary tournament selection based on rank and crowding distance
        p1 = crowded_tournament(population)
        p2 = crowded_tournament(population)

        # SBX crossover
        c1_vars, c2_vars = sbx_crossover(p1[:variables], p2[:variables])

        # polynomial mutation
        polynomial_mutation(c1_vars)
        polynomial_mutation(c2_vars)

        offspring << { variables: c1_vars }
        offspring << { variables: c2_vars }
      end

      offspring.first(@population_size)
    end

    # Binary tournament selection using the crowded comparison operator.
    # An individual is preferred if it has a lower rank, or if ranks are equal,
    # a higher crowding distance.
    def crowded_tournament(population)
      i = rand(population.size)
      j = rand(population.size - 1)
      j += 1 if j >= i

      a = population[i]
      b = population[j]

      if a[:rank] < b[:rank]
        a
      elsif b[:rank] < a[:rank]
        b
      elsif a[:crowding_distance] > b[:crowding_distance]
        a
      else
        b
      end
    end

    # Simulated Binary Crossover (SBX) as described in [DEB02].
    # This operator simulates the behavior of single-point crossover on
    # binary strings, producing two children from two parents.
    def sbx_crossover(p1, p2)
      c1 = p1.dup
      c2 = p2.dup

      if SecureRandom.random_number < @crossover_probability
        p1.each_index do |i|
          next unless SecureRandom.random_number < 0.5

          # crossover this variable
          next unless (p1[i] - p2[i]).abs > 1.0e-14

          min_val = @constraints[:min][i]
          max_val = @constraints[:max][i]

          if p1[i] < p2[i]
            y1 = p1[i]
            y2 = p2[i]
          else
            y1 = p2[i]
            y2 = p1[i]
          end

          # calculate beta_q from a uniform random number
          u = SecureRandom.random_number

          # compute spread factor beta for the lower bound
          beta = 1.0 + (2.0 * (y1 - min_val) / (y2 - y1))
          alpha = 2.0 - beta**-(@eta_c + 1.0)
          beta_q = if u <= 1.0 / alpha
                     (u * alpha)**(1.0 / (@eta_c + 1.0))
                   else
                     (1.0 / (2.0 - u * alpha))**(1.0 / (@eta_c + 1.0))
                   end

          child1 = 0.5 * ((y1 + y2) - beta_q * (y2 - y1))

          # compute spread factor beta for the upper bound
          beta = 1.0 + (2.0 * (max_val - y2) / (y2 - y1))
          alpha = 2.0 - beta**-(@eta_c + 1.0)
          beta_q = if u <= 1.0 / alpha
                     (u * alpha)**(1.0 / (@eta_c + 1.0))
                   else
                     (1.0 / (2.0 - u * alpha))**(1.0 / (@eta_c + 1.0))
                   end

          child2 = 0.5 * ((y1 + y2) + beta_q * (y2 - y1))

          # clamp to bounds
          c1[i] = [[child1, min_val].max, max_val].min
          c2[i] = [[child2, min_val].max, max_val].min
        end
      end

      [c1, c2]
    end

    # Polynomial mutation as described in [DEB02].
    # Each variable is mutated with probability @mutation_probability.
    def polynomial_mutation(individual)
      individual.each_index do |i|
        next unless SecureRandom.random_number < @mutation_probability

        min_val = @constraints[:min][i]
        max_val = @constraints[:max][i]
        y = individual[i]
        delta = max_val - min_val

        u = SecureRandom.random_number
        delta_q = if u < 0.5
                    (2.0 * u)**(1.0 / (@eta_m + 1.0)) - 1.0
                  else
                    1.0 - (2.0 * (1.0 - u))**(1.0 / (@eta_m + 1.0))
                  end

        individual[i] = [[y + delta_q * delta, min_val].max, max_val].min
      end
    end
  end
end
