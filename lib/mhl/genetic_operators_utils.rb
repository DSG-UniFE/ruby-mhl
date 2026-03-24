require 'securerandom'

module MHL
  # This module provides reusable genetic operators for multi-objective
  # optimization solvers, including Simulated Binary Crossover (SBX) and
  # polynomial mutation as described in [DEB02]:
  #   K. Deb, A. Pratap, S. Agarwal, T. Meyarivan, "A Fast and Elitist
  #   Multiobjective Genetic Algorithm: NSGA-II", IEEE Transactions on
  #   Evolutionary Computation, Vol. 6, No. 2, April 2002.
  #
  # These operators are designed to be included in solver classes that
  # define @constraints, @eta_c, @eta_m, @crossover_probability, and
  # @mutation_probability instance variables.
  module GeneticOperatorsUtils
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
    # Uses the asymmetric formulation where the perturbation depends on the
    # distance to the nearest bound, preventing excessive mutation near
    # boundaries.
    def polynomial_mutation(individual)
      individual.each_index do |i|
        next unless SecureRandom.random_number < @mutation_probability

        min_val = @constraints[:min][i]
        max_val = @constraints[:max][i]
        y = individual[i]
        range = max_val - min_val

        delta_1 = (y - min_val) / range
        delta_2 = (max_val - y) / range

        u = SecureRandom.random_number
        if u < 0.5
          xy = 1.0 - delta_1
          val = 2.0 * u + (1.0 - 2.0 * u) * xy**(@eta_m + 1.0)
          delta_q = val**(1.0 / (@eta_m + 1.0)) - 1.0
        else
          xy = 1.0 - delta_2
          val = 2.0 * (1.0 - u) + 2.0 * (u - 0.5) * xy**(@eta_m + 1.0)
          delta_q = 1.0 - val**(1.0 / (@eta_m + 1.0))
        end

        individual[i] = [[y + delta_q * range, min_val].max, max_val].min
      end
    end
  end
end
