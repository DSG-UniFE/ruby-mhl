require 'test_helper'

describe MHL::MultiSwarmQPSOSolver do

  it 'should solve a 2-dimension parabola in real space' do
    solver = MHL::MultiSwarmQPSOSolver.new(
      :swarm_size           => 20,
      :num_swarms           => 4,
      :random_position_func => lambda { Array.new(2) { rand(20).to_f } },
      :random_velocity_func => lambda { Array.new(2) { rand(10).to_f } },
      :exit_condition       => lambda {|generation,best_sample| best_sample[:height].abs < 0.001 },
      :logger               => :stdout,
      :log_level            => ENV['DEBUG'] ? Logger::DEBUG : Logger::WARN,
    )
    solver.solve(Proc.new{|position| -(position[0]**2 + position[1]**2) })
  end

end
