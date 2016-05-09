require 'test_helper'

describe MHL::QuantumPSOSolver do

  it 'should solve a 2-dimension parabola in real space' do
    solver = MHL::QuantumPSOSolver.new(
      :constraints          => {
        :min => [ -100, -100 ],
        :max => [  100,  100 ],
      },
      :exit_condition       => lambda {|iteration,best| best[:height].abs < 0.001 },
      :logger               => :stderr,
      :log_level            => ENV['DEBUG'] ? Logger::DEBUG : Logger::WARN,
    )
    solver.solve(Proc.new{|position| -(position[0]**2 + position[1]**2) })
  end

end
