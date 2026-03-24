require 'test_helper'

describe MHL::GeneticOperatorsUtils do
  # create a minimal host class that includes the module and provides
  # the instance variables the operators depend on
  let :operator_host_class do
    Class.new do
      include MHL::GeneticOperatorsUtils
      attr_accessor :constraints, :eta_c, :eta_m,
                    :crossover_probability, :mutation_probability

      def initialize(constraints, opts = {})
        @constraints = constraints
        @eta_c = opts[:eta_c] || 20.0
        @eta_m = opts[:eta_m] || 20.0
        @crossover_probability = opts[:crossover_probability] || 0.9
        @mutation_probability = opts[:mutation_probability] || 0.5
      end
    end
  end

  let :constraints do
    { min: [-5.0, -5.0, -5.0], max: [5.0, 5.0, 5.0] }
  end

  let :host do
    operator_host_class.new(constraints)
  end

  describe '#sbx_crossover' do
    it 'should return two children of the same dimension as the parents' do
      p1 = [1.0, 2.0, 3.0]
      p2 = [4.0, 3.0, 1.0]

      c1, c2 = host.sbx_crossover(p1, p2)

      assert_equal p1.size, c1.size
      assert_equal p2.size, c2.size
    end

    it 'should produce children within constraints' do
      100.times do
        p1 = constraints[:min].zip(constraints[:max]).map { |lo, hi| lo + SecureRandom.random_number * (hi - lo) }
        p2 = constraints[:min].zip(constraints[:max]).map { |lo, hi| lo + SecureRandom.random_number * (hi - lo) }

        c1, c2 = host.sbx_crossover(p1, p2)

        c1.each_with_index do |v, i|
          assert_operator v, :>=, constraints[:min][i]
          assert_operator v, :<=, constraints[:max][i]
        end
        c2.each_with_index do |v, i|
          assert_operator v, :>=, constraints[:min][i]
          assert_operator v, :<=, constraints[:max][i]
        end
      end
    end

    it 'should not modify the parents' do
      p1 = [1.0, 2.0, 3.0]
      p2 = [4.0, 3.0, 1.0]
      p1_orig = p1.dup
      p2_orig = p2.dup

      host.sbx_crossover(p1, p2)

      assert_equal p1_orig, p1
      assert_equal p2_orig, p2
    end

    it 'should return copies of parents when crossover probability is 0' do
      host_no_xover = operator_host_class.new(constraints, crossover_probability: 0.0)
      p1 = [1.0, 2.0, 3.0]
      p2 = [4.0, 3.0, 1.0]

      c1, c2 = host_no_xover.sbx_crossover(p1, p2)

      assert_equal p1, c1
      assert_equal p2, c2
    end
  end

  describe '#polynomial_mutation' do
    it 'should keep values within constraints' do
      100.times do
        individual = constraints[:min].zip(constraints[:max]).map do |lo, hi|
          lo + SecureRandom.random_number * (hi - lo)
        end

        host.polynomial_mutation(individual)

        individual.each_with_index do |v, i|
          assert_operator v, :>=, constraints[:min][i]
          assert_operator v, :<=, constraints[:max][i]
        end
      end
    end

    it 'should mutate in place' do
      # with high mutation probability, at least some values should change
      host_high_mut = operator_host_class.new(constraints, mutation_probability: 1.0)
      individual = [0.0, 0.0, 0.0]
      original = individual.dup

      # run enough times to be confident at least one mutation occurs
      changed = false
      10.times do
        test_ind = original.dup
        host_high_mut.polynomial_mutation(test_ind)
        changed = true if test_ind != original
        break if changed
      end

      assert changed, 'Polynomial mutation with probability 1.0 should modify the individual'
    end

    it 'should not mutate when probability is 0' do
      host_no_mut = operator_host_class.new(constraints, mutation_probability: 0.0)
      individual = [1.0, 2.0, 3.0]
      original = individual.dup

      host_no_mut.polynomial_mutation(individual)

      assert_equal original, individual
    end
  end
end
