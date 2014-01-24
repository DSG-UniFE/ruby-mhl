#ruby-mhl

A Ruby metaheuristics library


## Installation

I have not released ruby-mhl on RubyGems, yet. For the moment, if you want to
try it just place this line:

```ruby
gem 'mhl', git: 'https://github.com/mtortonesi/ruby-mhl.git'
```

in your Gemfile and run:

    bundle install


## Examples

Here is an example demonstrating how to solve the x^2 + y^2 equation with a
genetic algorithm:

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
  :exit_condition => lambda {|generation,best_sample| best_sample[:fitness] == 0}
)
solver.solve(Proc.new{|genotype| -(genotype[0]**2 + genotype[1]**2)  })
```

Other examples and a full documentation will be publised as ruby-mhl matures.


## License

MIT
