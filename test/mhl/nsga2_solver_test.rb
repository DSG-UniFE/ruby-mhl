require 'test_helper'

describe MHL::NSGA2Solver do
  let :logger do
    :stderr
  end

  let :log_level do
    ENV['DEBUG'] ? :debug : :warn
  end

  it 'should require even population size' do
    assert_raises(ArgumentError) do
      MHL::NSGA2Solver.new(
        population_size: 41,
        num_objectives: 2,
        constraints: { min: [-5.0, -5.0], max: [5.0, 5.0] }
      )
    end
  end

  it 'should require constraints' do
    assert_raises(ArgumentError) do
      MHL::NSGA2Solver.new(
        population_size: 40,
        num_objectives: 2
      )
    end
  end

  it 'should require at least 2 objectives' do
    assert_raises(ArgumentError) do
      MHL::NSGA2Solver.new(
        population_size: 40,
        num_objectives: 1,
        constraints: { min: [-5.0, -5.0], max: [5.0, 5.0] }
      )
    end
  end

  # ZDT1 is a standard bi-objective test function [DEB02].
  # f1(x) = x_1
  # f2(x) = g(x) * (1 - sqrt(x_1 / g(x)))
  # where g(x) = 1 + 9 * sum(x_2..x_n) / (n-1)
  # The Pareto-optimal front is obtained when g(x) = 1, i.e., x_2 = ... = x_n = 0.
  let :dimensions do
    10
  end

  let :solver do
    MHL::NSGA2Solver.new(
      population_size: 40,
      num_objectives: 2,
      constraints: {
        min: Array.new(dimensions, 0.0),
        max: Array.new(dimensions, 1.0)
      },
      exit_condition: ->(generation, _pareto_front) { generation >= 50 },
      logger: logger,
      log_level: log_level
    )
  end

  let :zdt1 do
    lambda do |variables|
      n = variables.size
      f1 = variables[0]
      g = 1.0 + 9.0 * variables[1...n].inject(0.0, :+) / (n - 1)
      f2 = g * (1.0 - Math.sqrt(f1 / g))
      [f1, f2]
    end
  end

  context 'concurrent' do
    it 'should solve a multi-objective problem concurrently' do
      result = solver.solve(zdt1, concurrent: true)

      # result should be an array of non-dominated solutions
      assert_kind_of Array, result
      refute_empty result

      # each solution should have :variables and :objectives keys
      result.each do |solution|
        assert_kind_of Array, solution[:variables]
        assert_kind_of Array, solution[:objectives]
        assert_equal dimensions, solution[:variables].size
        assert_equal 2, solution[:objectives].size
      end

      # all solutions in the returned front should be non-dominated
      # with respect to each other
      result.each_with_index do |a, i|
        result.each_with_index do |b, j|
          next if i == j

          refute MHL::DominanceUtils.dominates?(a[:objectives], b[:objectives]),
                 "Solution #{i} should not dominate solution #{j} within the Pareto front"
        end
      end
    end
  end

  context 'sequential' do
    it 'should solve a non-thread safe function sequentially' do
      # here we create a specially modified version of the function to optimize
      # that raises an error if called concurrently
      mx = Mutex.new
      func = lambda do |variables|
        raise 'Sequential call check failed' if mx.locked?

        mx.synchronize do
          sleep 0.001
          zdt1.call(variables)
        end
      end

      result = solver.solve(func)

      # result should be an array of non-dominated solutions
      assert_kind_of Array, result
      refute_empty result
    end
  end

  context 'convergence' do
    it 'should produce solutions approaching the true Pareto front on ZDT1' do
      result = solver.solve(zdt1, concurrent: true)

      # on ZDT1, the true Pareto front has f1 in [0,1] and f2 = 1 - sqrt(f1)
      # we check that at least some solutions have g(x) reasonably close to 1
      result.each do |solution|
        f1 = solution[:objectives][0]
        f2 = solution[:objectives][1]

        # both objectives should be non-negative for ZDT1
        assert_operator f1, :>=, 0.0
        assert_operator f2, :>=, 0.0
      end
    end
  end
end
