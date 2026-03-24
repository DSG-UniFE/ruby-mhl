require 'concurrent'
require 'logger'
require 'securerandom'

require 'mhl/dominance_utils'
require 'mhl/genetic_operators_utils'

module MHL
  # This solver implements the MOEA/D (Multi-Objective Evolutionary Algorithm
  # Based on Decomposition) as described in [ZHLI07]:
  #   Q. Zhang, H. Li, "MOEA/D: A Multiobjective Evolutionary Algorithm Based
  #   on Decomposition", IEEE Transactions on Evolutionary Computation,
  #   Vol. 11, No. 6, December 2007.
  #
  # MOEA/D decomposes a multi-objective optimization problem into a set of
  # scalar subproblems using uniformly distributed weight vectors and
  # optimizes them simultaneously. Each subproblem is optimized using
  # information from its neighboring subproblems only, defined by proximity
  # of weight vectors.
  #
  # This implementation uses the Tchebycheff scalarization approach, SBX
  # crossover and polynomial mutation as genetic operators.
  #
  # All objectives are minimized. If you need to maximize an objective,
  # negate it in the objective function.
  class MOEADSolver
    include GeneticOperatorsUtils

    attr_reader :best_positions

    # Default number of weight vectors (population size).
    # For MOEA/D, each weight vector corresponds to one individual.
    DEFAULT_POPULATION_SIZE = 100

    # Default neighborhood size (T in [ZHLI07])
    DEFAULT_NEIGHBORHOOD_SIZE = 20

    # SBX crossover distribution index [DEB02]
    DEFAULT_ETA_C = 20.0

    # Polynomial mutation distribution index [DEB02]
    DEFAULT_ETA_M = 20.0

    # Default crossover probability
    DEFAULT_CROSSOVER_PROBABILITY = 1.0

    def initialize(opts = {})
      @population_size = (opts[:population_size] || DEFAULT_POPULATION_SIZE).to_i
      unless @population_size and @population_size > 0
        raise ArgumentError, 'Population size must be a positive integer!'
      end

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

      @neighborhood_size = (opts[:neighborhood_size] || DEFAULT_NEIGHBORHOOD_SIZE).to_i
      raise ArgumentError, 'Neighborhood size must not exceed population size!' if @neighborhood_size > @population_size

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

      @best_positions = []

      return unless @logger && opts[:log_level]

      @logger.level = opts[:log_level]
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
      # Step 1: Initialization [ZHLI07, Section III-D, Step 1]

      # Step 1.1: Generate uniformly distributed weight vectors
      weights = generate_weight_vectors(@population_size, @num_objectives)
      n = weights.size

      # Step 1.2: Compute neighborhoods based on Euclidean distances
      # between weight vectors. B(i) contains the indices of the T closest
      # weight vectors to lambda^i.
      neighborhoods = compute_neighborhoods(weights, @neighborhood_size)

      # Step 1.3: Initialize population
      population = initialize_population(n)

      # Step 1.4: Evaluate population
      evaluate_population(population, func, params[:concurrent])

      # Step 1.5: Initialize the reference point z* (ideal point)
      # z*_j = min { f_j(x^i) } for each objective j
      ideal_point = Array.new(@num_objectives) do |j|
        population.map { |ind| ind[:objectives][j] }.min
      end

      # initialize variables
      gen = 0

      # default behavior is to loop forever
      begin
        gen += 1
        @logger.info("MOEA/D - Starting generation #{gen}") if @logger

        # Step 2: Update [ZHLI07, Section III-D, Step 2]
        n.times do |i|
          # Step 2.1: Reproduction
          # randomly select two indices k, l from the neighborhood B(i)
          k = neighborhoods[i].sample
          l = neighborhoods[i].sample

          # generate a new solution y using SBX crossover and polynomial
          # mutation from x^k and x^l
          c1_vars, = sbx_crossover(population[k][:variables], population[l][:variables])
          polynomial_mutation(c1_vars)

          # Step 2.2: Evaluate the new solution
          child_objectives = func.call(c1_vars)

          # Step 2.3: Update the reference point z*
          @num_objectives.times do |j|
            ideal_point[j] = child_objectives[j] if child_objectives[j] < ideal_point[j]
          end

          # Step 2.4: Update neighboring solutions
          # For each index j in B(i), if the Tchebycheff value of the child
          # is better than x^j, replace x^j with the child.
          neighborhoods[i].each do |j|
            child_te = tchebycheff(child_objectives, weights[j], ideal_point)
            current_te = tchebycheff(population[j][:objectives], weights[j], ideal_point)
            population[j] = { variables: c1_vars.dup, objectives: child_objectives.dup } if child_te <= current_te
          end
        end

        # extract the current non-dominated set for tracking and exit condition
        fronts = DominanceUtils.fast_non_dominated_sort(population)
        pareto_front_indices = fronts[0]
        pareto_front = pareto_front_indices.map { |i| population[i] }

        @best_positions << pareto_front.size

        # print results
        @logger.info "> gen #{gen}, pareto front size: #{pareto_front.size}" if @logger and !@quiet
      end while @exit_condition.nil? or !@exit_condition.call(gen, pareto_front)

      # return the non-dominated solutions from the final population
      pareto_front.map do |ind|
        { variables: ind[:variables].dup, objectives: ind[:objectives].dup }
      end
    end

    private

    def initialize_population(size)
      positions = if @start_population
                    @start_population
                  elsif @random_position_func
                    Array.new(size) { @random_position_func.call }
                  else
                    # initialize using constraints, similar to SPSO 2006-2011
                    # random initialization [CLERC12]
                    min = @constraints[:min]
                    max = @constraints[:max]
                    Array.new(size) do
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

    # Tchebycheff scalarization approach [ZHLI07, eq. 4].
    #
    #   g^te(x | lambda, z*) = max { lambda_j * | f_j(x) - z*_j | }
    #                          1 <= j <= m
    #
    # A small epsilon is added to zero weights to avoid degenerate behavior
    # when a weight component is exactly zero.
    def tchebycheff(objectives, weight, ideal_point)
      objectives.each_with_index.map do |f_j, j|
        w_j = [weight[j], 1.0e-6].max
        w_j * (f_j - ideal_point[j]).abs
      end.max
    end

    # Generate uniformly distributed weight vectors using the Das and Dennis
    # systematic approach [DAS98]:
    #   I. Das, J.E. Dennis, "Normal-Boundary Intersection: A New Method for
    #   Generating the Pareto Surface in Nonlinear Multicriteria Optimization
    #   Problems", SIAM Journal on Optimization, Vol. 8, No. 3, 1998.
    #
    # For m objectives, the number of divisions H is chosen as the largest
    # integer such that C(H+m-1, m-1) <= desired_size. The actual number of
    # weight vectors may differ slightly from desired_size.
    def generate_weight_vectors(desired_size, num_objectives)
      if num_objectives == 2
        # for bi-objective problems, generate evenly spaced weights directly
        h = desired_size - 1
        h = 1 if h < 1
        return (0..h).map { |i| [i.to_f / h, 1.0 - i.to_f / h] }
      end

      # find the largest H such that C(H+m-1, m-1) <= desired_size
      h = 1
      h += 1 while combination_count(h + num_objectives - 1, num_objectives - 1) <= desired_size
      h -= 1
      h = 1 if h < 1

      # generate all weight vectors with components that sum to 1
      vectors = []
      generate_recursive(num_objectives, h, 0, [], vectors)
      vectors
    end

    # Recursively generate weight vectors whose components are multiples
    # of 1/H and sum to 1.
    def generate_recursive(num_objectives, h, depth, current, result)
      if depth == num_objectives - 1
        remaining = h - current.inject(0, :+)
        result << (current + [remaining.to_f / h])
      else
        sum_so_far = current.inject(0, :+)
        (0..(h - sum_so_far)).each do |i|
          generate_recursive(num_objectives, h, depth + 1, current + [i], result)
        end
      end
    end

    # Compute C(n, k) = n! / (k! * (n-k)!)
    def combination_count(n, k)
      return 1 if k == 0 || k == n

      k = n - k if k > n - k
      (1..k).inject(1) { |result, i| result * (n - i + 1) / i }
    end

    # Compute neighborhoods based on Euclidean distances between weight
    # vectors. For each weight vector i, B(i) contains the indices of the
    # T closest weight vectors (including i itself).
    def compute_neighborhoods(weights, neighborhood_size)
      n = weights.size
      t = [neighborhood_size, n].min

      distances = Array.new(n) do |i|
        Array.new(n) do |j|
          if i == j
            0.0
          else
            Math.sqrt(weights[i].zip(weights[j]).inject(0.0) { |s, (a, b)| s + (a - b)**2 })
          end
        end
      end

      Array.new(n) do |i|
        (0...n).sort_by { |j| distances[i][j] }.first(t)
      end
    end
  end
end
