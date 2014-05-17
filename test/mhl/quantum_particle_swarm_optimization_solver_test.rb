require 'test_helper'

describe MHL::QuantumPSOSolver do

  it 'should solve a 2-dimension parabola in real space' do
    solver = MHL::QuantumPSOSolver.new(
      :swarm_size           => 40,
      :random_position_func => lambda { Array.new(2) { rand(20) } },
      :exit_condition       => lambda {|generation,best_sample| best_sample[:height].abs < 0.001 },
      :logger               => :stderr,
      :log_level            => ENV['DEBUG'] ? Logger::DEBUG : Logger::WARN,
    )
    solver.solve(Proc.new{|position| -(position[0]**2 + position[1]**2) })
  end

end
