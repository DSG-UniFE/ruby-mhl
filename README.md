# ruby-mhl - A Ruby metaheuristics library

ruby-mhl is a scientific library that provides a fairly large array of advanced
computational intelligence methods for continuous optimization solutions.

More specifically, ruby-mhl currently supports several implementations of
Genetic Algorithms (bitstring and integer vector genotype representations) and
Particle Swarm Optimization (constrained PSO, quantum-inspired PSO, and a
multi-swarm version of quantum-inspired PSO), extended with adaptation 
mechanisms to provide support for dynamic optimization problems.

ruby-mhl was designed for _high duty_ target functions, whose evaluation
typically involves one or more simulation runs, possibly defined on very
complex domains (or search spaces), and implemented in JRuby for performance
reasons. To this end, ruby-mhl automatically takes advantage of the parallelism
provided by the processor.


## Installation

To install ruby-mhl you first have to install Java and JRuby. This is a system
dependent step, so I won't show you how to do it. However, if you are on Linux
or OS X I recommend you to use [rbenv](https://github.com/rbenv/rbenv) to
install and manage your Ruby installations.

Once you have JRuby installed, you need to install bundler:

    gem install bundler


### Stable version

You can get the stable version of ruby-mhl by installing the mhl gem from
RubyGems:

    gem install mhl

or by adding:

```ruby
gem 'mhl'
```

to your application's Gemfile and running:

    bundle install

### Development version

If you want to try the development version of ruby-mhl, instead, just place
this line:

```ruby
gem 'mhl', git: 'https://github.com/mtortonesi/ruby-mhl.git'
```

in your Gemfile and run:

    bundle install


## Genetic Algorithm (GA)

ruby-mhl provides a GA solver capable of working with either the traditional
bitstring chromosome representation or a integer vector representation variant.

#### Example: Solving the parabola function with a integer vector GA

Here is an example demonstrating how to find the argument that minimizes the
2-dimension parabola _f(x) = x<sub>1</sub><sup>2</sup> +
x<sub>2</sub><sup>2</sup>_ equation with a genetic algorithm:

```ruby
require 'mhl'

solver = MHL::GeneticAlgorithmSolver.new(
  :population_size           => 80,
  :genotype_space_type       => :integer,
  :mutation_probability      => 0.5,
  :recombination_probability => 0.5,
  :genotype_space_conf       => {
    :dimensions         => 2,
    :recombination_type => :intermediate,
    :random_func        => lambda { Array.new(2) { rand(100) } }
  },
  :exit_condition => lambda {|generation,best| best[:fitness] == 0}
)
solver.solve(Proc.new{|x| -(x[0] ** 2 + x[1] ** 2) })
```


## Particle Swarm Optimization (PSO)

ruby-mhl implements the constrained version of PSO, defined by equation 4.30 of
[SUN11], which we report here for full clarity. The velocity and position
update equation for particle _i_ are:

<!--
```latex
\begin{aligned}
    V_{i,j}(t+1) =& \; \chi [ V_{i,j}(t) + \\
                  & \quad C_1 * r_{i,j}(t) * (P_{i,j}(t) - X_{i,j}(t)) + \\
                  & \quad C_2 * R_{i,j}(t) * (G_j(t) - X_{i,j}(t)) ] \\
    X_{i,j}(t+1) =& \; X_{i,j}(t) + V_{i,j}(t+1)
\end{aligned}
```
-->

![Movement equations for Constrained PSO](http://mathurl.com/z9zxe8q.png)

In which _X<sub>i</sub>(t) = (X<sub>i,1</sub>(t), ..., X<sub>i,N</sub>(t))_ is
the particle location, whose components _X<sub>i,j</sub>(t)_ represent the
decision variables of the problem; _V<sub>i</sub>(t) = (V<sub>i,1</sub>(t),
..., V<sub>i,N</sub>(t))_ is a velocity vector which captures the movement of
the particle; _P<sub>i</sub>(t) = (P<sub>i,1</sub>(t), ...,
P<sub>i,N</sub>(t))_ is a _particle attractor_ representing the 'highest'
(best) position that the particle has encountered so far; _G(t)_ is the _swarm
attractor_, representing the 'highest' (best) position that the entire swarm
has encountered so far; _r<sub>i,j</sub>(t)_ and _R<sub>i,j</sub>(t)_ are
random sequences uniformly sampled in the (0,1) interval; and _C<sub>1</sub>_
and _C<sub>2</sub>_ are constants.

Note that, in order to guarantee convergence, we must have:

<!--
```latex
\begin{aligned}
    \phi =& C_1 + C_2 > 4\\
    \chi =& \frac{2}{\lvert 2-\phi-\sqrt{\phi^2-4\phi} \rvert}
\end{aligned}
```
-->

![Convergence criteria for Constrained PSO](http://mathurl.com/zjakqww.png)

As a result, by default ruby-mhl sets _C<sub>1</sub> = C<sub>2</sub> = 2.05_
and calculates &chi; accordingly (approximately 0.72984), which is considered
the best practice [BLACKWELL04]. For more information about this (much more
than you'll ever want to know, believe me) please refer to [CLERC02].

#### Example: Solving the parabola function with PSO

Here is an example demonstrating how to find the argument that minimizes the
2-dimension parabola _f(x) = x<sub>1</sub><sup>2</sup> +
x<sub>2</sub><sup>2</sup>_ equation with PSO:

```ruby
require 'mhl'

solver = MHL::ParticleSwarmOptimizationSolver.new(
  :swarm_size     => 40, # 40 is the default swarm size
  :constraints    => {
    :min => [ -100, -100 ],
    :max => [  100,  100 ],
  },
  :exit_condition => lambda {|iteration,best| best[:height].abs < 0.001 },
)
solver.solve(Proc.new{|x| -(x[0] ** 2 + x[1] ** 2) })
```


## Quantum-Inspired Particle Swarm Optimization (QPSO)

Quantum-inspired PSO is another particularly interesting PSO variant. It aims
at simulating interactions between a group of humans by borrowing concepts
from (the uncertainty typical of) quantum mechanics.

ruby-mhl implements the Quantum-inspired version of PSO (QPSO), Type 2, as
defined by equation 4.82 of [SUN11], which we report here for full clarity.

<!--
```latex
\begin{equation}
\begin{aligned}
  C_j(t)       &= \frac{1}{M} \sum_{i=1}^{M} P_{i,j}(t) \\
  p_{i,j}(t)   &= \phi_{i,j}(t) P_{i,j}(t) + (1-\phi_{i,j}(t)) G_j(t) \\
  X_{i,j}(t+1) &= p_{i,j}(t) + \alpha \lvert X_{i,j}(t) - C_j(t) \rvert \ln \frac{1}{u_{i,j}(t+1)}
\end{aligned}
\end{equation}
```
-->

![Movement Equations for Quantum-inspired PSO](http://mathurl.com/jkw88ue.png)

where _P<sub>i</sub>(t)_ is the personal best of particle _i_; _C(t)_ is
the mean of the personal bests of all the particles in the swarm; _G(t)_ is the
swarm attractor; and _&phi;<sub>i,j</sub>(t)_ and _u<sub>i,j</sub>(t+1)_ are
sequences of random numbers uniformly distributed on the (0,1) interval.


#### Example: Solving the parabola function with QPSO

Here is an example demonstrating how to find the argument that minimizes the
2-dimension parabola _f(x) = x<sub>1</sub><sup>2</sup> +
x<sub>2</sub><sup>2</sup>_ equation with PSO:

```ruby
require 'mhl'

solver = MHL::QuantumPSOSolver.new(
  :swarm_size     => 40, # 40 is the default swarm size
  :constraints    => {
    :min => [ -100, -100 ],
    :max => [  100,  100 ],
  },
  :exit_condition => lambda {|iteration,best| best[:height].abs < 0.001 },
)
solver.solve(Proc.new{|x| -(x[0] ** 2 + x[1] ** 2) })
```


## License

MIT


## Publications

ruby-mhl was used in the following scientific publications:

[TORTONESI16] M. Tortonesi, L. Foschini, "Business-driven Service Placement for
Highly Dynamic and Distributed Cloud Systems", IEEE Transactions on Cloud
Computing, 2016 (in print).

[TORTONESI15] M.Tortonesi, "Exploring Continuous Optimization Solutions for
Business-driven IT Managment Problems", in Proceedings of the 14th
IFIP/IEEE Integrated Network Management Symposium (IM 2015) - Short papers
track, 11-15 May 2015, Ottawa, Canada.

[GRABARNIK14] G. Grabarnik, L. Shwartz, M. Tortonesi, "Business-Driven
Optimization of Component Placement for Complex Services in Federated Clouds",
in Proceedings of the 14th IEEE/IFIP Network Operations and Management
Symposium (NOMS 2014) - Mini-conference track, 5-9 May 2014, Krakow, Poland.

[FOSCHINI13] L. Foschini, M. Tortonesi, "Adaptive and Business-driven Service
Placement in Federated Cloud Computing Environments", in Proceedings of the 8th
IFIP/IEEE International Workshop on Business-driven IT Management (BDIM 2013),
27 May 2013, Ghent, Belgium.

If you are interested in ruby-mhl, please consider reading and citing them.


## Acknowledgements

The research work that led to the development of ruby-mhl was supported in part by
the [DICET - INMOTO - ORganization of Cultural HEritage for Smart
Tourism and Real-time Accessibility (OR.C.HE.S.T.R.A.)](http://www.ponrec.it/open-data/progetti/scheda-progetto?ProgettoID=5835)
project, funded by the Italian Ministry of University and Research on Axis II
of the National operative programme (PON) for Research and Competitiveness
2007-13 within the call 'Smart Cities and Communities and Social Innovation'
(D.D. n.84/Ric., 2 March 2012).


## References

[SUN11] Jun Sun, Choi-Hong Lai, Xiao-Jun Wu, "Particle Swarm Optimisation:
Classical and Quantum Perspectives", CRC Press, 2011.

[CLERC02] M. Clerc, J. Kennedy, "The particle swarm - explosion,
stability, and convergence in a multidimensional complex space", IEEE
Transactions on Evolutionary Computation, Vol. 6, No. 1, pp. 58-73,
2002, DOI: 10.1109/4235.985692

[BLACKWELL04] Tim Blackwell, Jürgen Branke, "Multi-swarm Optimization in
Dynamic Environments", Applications of Evolutionary Computing, pp. 489-500,
Springer, 2004. DOI: 10.1007/978-3-540-24653-4\_50

[REZAEEJORDEHI13] A. Rezaee Jordehi, J. Jasni, "Parameter selection in particle
swarm optimisation: a survey", Journal of Experimental & Theoretical Artificial
Intelligence, Vol. 25, No. 4, pp. 527-542, 2013. DOI: 10.1080/0952813X.2013.782348

[CLERC12] M. Clerc, "Standard Particle Swarm Optimisation - From 2006 to 2011",
available at: [http://clerc.maurice.free.fr/pso/SPSO\_descriptions.pdf](http://clerc.maurice.free.fr/pso/SPSO_descriptions.pdf)
