#ruby-mhl

A Ruby metaheuristics library


## Installation

### Stable version

You can get the stable version of ruby-mhl by installing the mhl gem from
RubyGems:

    gem install mhl

### Development version

If you want to try the development version of ruby-mhl, instead, just place
this line:

```ruby
gem 'mhl', git: 'https://github.com/mtortonesi/ruby-mhl.git'
```

in your Gemfile and run:

    bundle install


## Examples

Here is an example demonstrating how to find the argument that minimizes the
2-dimension parabola x_1 ^ 2 + x_2 ^ 2 equation with a genetic algorithm:

```ruby
require 'mhl'

solver = MHL::GeneticAlgorithmSolver.new(
  :population_size           => 40,
  :genotype_space_type       => :integer,
  :mutation_probability      => 0.5,
  :recombination_probability => 0.5,
  :genotype_space_conf       => {
    :dimensions         => 2,
    :recombination_type => :intermediate,
    :random_func        => lambda { Array.new(2) { rand(20) } }
  },
  :exit_condition => lambda {|generation,best| best[:fitness] == 0}
)
solver.solve(Proc.new{|x| -(x[0] ** 2 + x[1] ** 2) })
```

and with particle swarm optimization:

```ruby
require 'mhl'

solver = MHL::ParticleSwarmOptimizationSolver.new(
  :swarm_size           => 40,
  :random_position_func => lambda { Array.new(2) { rand(20) } },
  :random_velocity_func => lambda { Array.new(2) { rand(10) } },
  :exit_condition       => lambda {|generation,best| best[:height].abs < 0.001 },
)
solver.solve(Proc.new{|x| -(x[0] ** 2 + x[1] ** 2) })
```

Other examples and a full documentation will be publised as ruby-mhl matures.


## License

MIT
