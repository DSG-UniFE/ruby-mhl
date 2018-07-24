require 'test_helper'

describe MHL::ParticleSwarmOptimizationSolver do

  let :logger do
    :stderr
  end

  let :log_level do
    ENV['DEBUG'] ? :debug : :warn
  end

  let :solver do
     MHL::ParticleSwarmOptimizationSolver.new(
      constraints: {
        min: [ -100, -100, -100, -100, -100 ],
        max: [  100,  100,  100,  100,  100 ],
      },
      exit_condition: lambda {|iteration,best| best[:height].abs < 0.001 },
      logger: logger,
      log_level: log_level,
    )
  end

  context 'concurrent' do

    it 'should solve a thread-safe function concurrently' do
      func = -> position do
        -(position.inject(0.0) {|s,x| s += x**2 })
      end

      solver.solve(func, concurrent: true)
    end

  end

  context 'sequential' do

    it 'should solve a non-thread safe function sequentially' do
      # here we create a specially modified version of the function to optimize
      # that raises an error if called concurrently
      mx = Mutex.new
      func = -> position do
        raise "Sequential call check failed" if mx.locked?
        mx.synchronize do
          sleep 0.005
          -(position.inject(0.0) {|s,x| s += x**2 })
        end
      end

      solver.solve(func)
    end

  end

end
