require 'test_helper'

describe MHL::MultiSwarmQPSOSolver do
  let :logger do
    :stderr
  end

  let :log_level do
    ENV['DEBUG'] ? :debug : :warn
  end

  let :max_iterations do
    5000
  end

  let :solver do
    MHL::MultiSwarmQPSOSolver.new(
      num_swarms: 4,
      swarm_size: 10,
      constraints: {
        min: [-100, -100, -100, -100, -100],
        max: [100,  100,  100,  100,  100]
      },
      exit_condition: lambda { |iteration, best|
        iteration >= max_iterations || best[:height].abs < 0.001
      },
      logger: logger,
      log_level: log_level
    )
  end

  # 5-dimensional negative sphere function: maximum is 0 at origin
  let :func do
    ->(position) { -(position.inject(0.0) { |s, x| s += x**2 }) }
  end

  context 'sequential' do
    it 'should solve a non-thread safe function sequentially' do
      # here we create a specially modified version of the function to optimize
      # that raises an error if called concurrently
      mx = Mutex.new
      sequential_func = lambda do |position|
        raise 'Sequential call check failed' if mx.locked?

        mx.synchronize do
          sleep 0.005
          -(position.inject(0.0) { |s, x| s += x**2 })
        end
      end

      result = solver.solve(sequential_func)
      assert result, 'Solver should return a result'
      assert result[:height], 'Result should have a height'
    end

    it 'should converge to the optimum of a negative sphere function' do
      result = solver.solve(func)

      assert result, 'Solver should return a result'
      assert_operator result[:height], :>=, -0.001,
                      "Expected height close to 0 (optimum), got #{result[:height]}"
      result[:position].each_with_index do |x_i, i|
        assert_in_delta 0.0, x_i, 1.0,
                        "Expected position[#{i}] close to 0, got #{x_i}"
      end
    end
  end
end
