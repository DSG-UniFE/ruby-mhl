require 'concurrent'
require 'facter'

# Setup thread pool size as 4 times the number of CPUs in the current machine
Concurrent::Future.thread_pool = Concurrent::FixedThreadPool.new(Facter.processorcount.to_i * 4)
