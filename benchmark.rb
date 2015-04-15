require "benchmark/ips"
require 'diffy'
require 'diffy/ruby_diff'

strings = [
  File.read('lib/diffy/diff.rb'),
  File.read('lib/diffy/ruby_diff.rb')
]

Benchmark.ips do |benchmark|
  benchmark.report('shell out to `diff` command') do
    Diffy::Diff.new(*strings).to_s
  end

  benchmark.report('ruby with Diff::LCS') do
    Diffy::RubyDiff.new(*strings).to_s
  end

  benchmark.compare!
end

# Calculating -------------------------------------
# shell out to `diff` command
#                             19 i/100ms
#  ruby with Diff::LCS        14 i/100ms
# -------------------------------------------------
# shell out to `diff` command
#                           198.8 (±2.0%) i/s -       1007 in   5.066639s
#  ruby with Diff::LCS      145.2 (±2.8%) i/s -        728 in   5.017490s
#
# Comparison:
# shell out to `diff` command:      198.8 i/s
#  ruby with Diff::LCS:      145.2 i/s - 1.37x slower
