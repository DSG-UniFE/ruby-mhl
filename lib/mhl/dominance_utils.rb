module MHL
  # This module provides reusable utilities for multi-objective optimization,
  # including non-dominated sorting and crowding distance assignment.
  #
  # Non-dominated sorting is based on the fast algorithm described in [DEB02]:
  #   K. Deb, A. Pratap, S. Agarwal, T. Meyarivan, "A Fast and Elitist
  #   Multiobjective Genetic Algorithm: NSGA-II", IEEE Transactions on
  #   Evolutionary Computation, Vol. 6, No. 2, April 2002.
  #
  # These utilities are designed to be reused across different MOO solvers
  # (e.g., NSGA-II, SPEA2, MOEA/D).
  module DominanceUtils
    # Performs fast non-dominated sorting on a population.
    #
    # Each member of the population must respond to [:objectives], returning
    # an array of objective values. All objectives are assumed to be minimized.
    #
    # Returns an array of fronts, where each front is an array of indices into
    # the original population. The first front (index 0) is the Pareto-optimal
    # front, the second front contains individuals dominated only by the first
    # front, and so on.
    #
    # This implements the fast non-dominated sort from [DEB02], Algorithm 1.
    def self.fast_non_dominated_sort(population)
      n = population.size
      # domination_count[i] = number of individuals that dominate i
      domination_count = Array.new(n, 0)
      # dominated_set[i] = set of indices that individual i dominates
      dominated_set = Array.new(n) { [] }

      fronts = []
      current_front = []

      n.times do |p|
        n.times do |q|
          next if p == q

          if dominates?(population[p][:objectives], population[q][:objectives])
            dominated_set[p] << q
          elsif dominates?(population[q][:objectives], population[p][:objectives])
            domination_count[p] += 1
          end
        end
        current_front << p if domination_count[p] == 0
      end

      until current_front.empty?
        fronts << current_front
        next_front = []
        current_front.each do |p|
          dominated_set[p].each do |q|
            domination_count[q] -= 1
            next_front << q if domination_count[q] == 0
          end
        end
        current_front = next_front
      end

      fronts
    end

    # Computes crowding distance for a single front.
    #
    # Parameter front_indices is an array of indices into the population.
    # Parameter population is the full population array (each member must
    # respond to [:objectives]).
    #
    # Returns a hash mapping each index to its crowding distance value.
    # Boundary solutions (with minimum or maximum value for any objective)
    # receive an infinite crowding distance.
    #
    # This implements the crowding distance assignment from [DEB02], Algorithm 2.
    def self.crowding_distance_assignment(front_indices, population)
      distances = {}
      front_indices.each { |i| distances[i] = 0.0 }

      return distances if front_indices.size <= 2

      num_objectives = population[front_indices.first][:objectives].size

      num_objectives.times do |m|
        # sort front by objective m
        sorted = front_indices.sort_by { |i| population[i][:objectives][m] }

        # boundary points get infinite distance
        distances[sorted.first] = Float::INFINITY
        distances[sorted.last]  = Float::INFINITY

        # calculate the range for normalization
        obj_min = population[sorted.first][:objectives][m]
        obj_max = population[sorted.last][:objectives][m]
        range = obj_max - obj_min

        # skip this objective if range is zero (all values identical)
        next if range == 0.0

        # update distances for interior points
        (1...(sorted.size - 1)).each do |k|
          distances[sorted[k]] += (population[sorted[k + 1]][:objectives][m] -
                                   population[sorted[k - 1]][:objectives][m]) / range
        end
      end

      distances
    end

    # Returns true if solution a dominates solution b (all objectives minimized).
    # A solution a dominates b if a is no worse than b in all objectives and
    # strictly better in at least one.
    def self.dominates?(a_objectives, b_objectives)
      dominated = false
      a_objectives.zip(b_objectives).each do |a_i, b_i|
        return false if a_i > b_i

        dominated = true if a_i < b_i
      end
      dominated
    end
  end
end
