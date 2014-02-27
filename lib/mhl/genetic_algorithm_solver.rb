require 'erv'

require 'mhl/bitstring_genotype_space'
require 'mhl/integer_genotype_space'


module MHL

  class GeneticAlgorithmSolver
    def initialize(opts)
      @population_size = opts[:population_size].to_i
      unless @population_size and @population_size.even?
        raise ArgumentError, 'Even population size required!'
      end

      # perform genotype space-specific configuration
      case opts[:genotype_space_type]
      when :integer
        @genotype_space = IntegerVectorGenotypeSpace.new(opts[:genotype_space_conf])

        begin
          p_m = opts[:mutation_probability].to_f
          @mutation_rv = \
            ERV::RandomVariable.new(:distribution           => :geometric,
                                    :probability_of_success => p_m)
        rescue
          raise ArgumentError, 'Mutation probability configuration is wrong.'
        end

        begin
          p_r = opts[:recombination_probability].to_f
          @recombination_rv = \
            ERV::RandomVariable.new(:distribution => :uniform,
                                    :min_value    => -p_r,
                                    :max_value    => 1.0 + p_r)
        rescue
          raise ArgumentError, 'Recombination probability configuration is wrong.'
        end

      when :bitstring
        @genotype_space   = BitstringGenotypeSpace.new(opts[:genotype_space_conf])
        @recombination_rv = ERV::RandomVariable.new(:distribution => :uniform, :max_value => 1.0)
        @mutation_rv      = ERV::RandomVariable.new(:distribution => :uniform, :max_value => 1.0)

      else
        raise ArgumentError, 'Only integer and bitstring genotype representations are supported!'
      end

      @exit_condition   = opts[:exit_condition]
      @start_population = opts[:genotype_space_conf][:start_population]
    end


    # This is the method that solves the optimization problem
    #
    # Parameter func is supposed to be a method (or a Proc, a lambda, or any callable
    # object) that accepts the genotype as argument (that is, the set of
    # parameters) and returns the phenotype (that is, the function result)
    def solve(func)
      # setup population
      if @start_population.nil?
        population = Array.new(@population_size) do
          # generate random genotype according to the chromosome type
          { :genotype => @genotype_space.get_random }
        end
      else
        population = @start_population.map do |x|
          { :genotype => x }
        end
      end

      # initialize variables
      gen = 0
      overall_best = nil

      # default behavior is to loop forever
      begin
        gen += 1
        puts "Starting generation #{gen} at #{Time.now}"

        # assess fitness for every member of the population
        population.each do |s|
          s[:task] = Concurrent::Future.new { func.call(s[:genotype]) }
        end

        # wait for all the evaluations to end
        population.each do |s|
          s[:fitness] = s[:task].value
        end

        # find fittest member
        population_best = population.max_by {|x| x[:fitness] }

        # calculate overall best
        if overall_best.nil?
          overall_best = population_best
        else
          overall_best = [ overall_best, population_best ].max_by {|x| x[:fitness] }
        end

        # print results
        puts "> gen #{gen}, best: #{overall_best[:genotype]}, #{overall_best[:fitness]}"

        # selection by binary tournament
        children = new_generation(population)

        # update population and generation number
        population = children
      end while @exit_condition.nil? or !@exit_condition.call(gen, overall_best)
    end


    private

      # reproduction with point mutation and one-point crossover
      def new_generation(population)
        population_size = population.size

        # check correct population size
        # TODO: disable this check in non-debugging mode
        raise ArgumentError, 'Population size error!' if population_size != @population_size

        # prepare children
        children = []

        # select members to reproduce through binary tournament
        selected = Array.new(@population_size) { |i| binary_tournament(population) }
        selected.shuffle!

        # reproduction
        selected.each_slice(2) do |p1, p2|
          # get two new samples...
          c1, c2 = @genotype_space.reproduce_from(p1, p2, @mutation_rv, @recombination_rv)

          # ...and add them to the children population
          children.push(c1, c2)

          # check correct population size
          # TODO: disable this check in non-debugging mode
          raise 'Children size error!' if children.size > population_size
        end

        return children
      end

      # This method implements binary tournament selection, which is probably
      # the most popular selection method for genetic algorithms
      def binary_tournament(population)
        i = rand(population.size)
        j = rand(population.size - 1)
        j += 1 if j >= i

        select_fittest(population[i], population[j])
      end

      def select_fittest(*a)
        # TODO: disable this check in non-debugging mode
        raise 'Attempting to select the fittest sample of an empty population!' if a.empty?
        a.max_by {|x| x[:fitness] }
      end
  end

end
