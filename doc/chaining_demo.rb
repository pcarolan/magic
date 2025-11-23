#!/usr/bin/env ruby
# Demonstration of Magic chaining with Fluent API

require_relative 'magic'

puts "=" * 60
puts "Magic Fluent API Chaining Demonstration"
puts "=" * 60
puts

# Example 1: Single method call (works as before)
puts "Example 1: Single method call"
puts "-" * 40
magic = Magic.new
result = magic.random_number
puts "Result type: #{result.class}"
puts "Result value (via .to_s): #{result.to_s}"
puts "Result value (via .result): #{result.result}"
puts

# Example 2: Chaining two methods
puts "Example 2: Chaining two methods"
puts "-" * 40
result = magic.random_number.multiply_by(5)
puts "Result type: #{result.class}"
puts "Chained result: #{result.to_s}"
puts "History length: #{result.instance_variable_get(:@history).length} steps"
puts

# Example 3: Chaining three methods
puts "Example 3: Chaining three methods"
puts "-" * 40
result = magic.random_number.multiply_by(5).add(10)
puts "Result: #{result}"  # Auto-calls to_s
puts "History: #{result.inspect}"
puts

# Example 4: Using result explicitly
puts "Example 4: Accessing intermediate results"
puts "-" * 40
step1 = magic.get_number
puts "Step 1 result: #{step1.result}"

step2 = step1.double_it
puts "Step 2 result: #{step2.result}"

step3 = step2.add(100)
puts "Step 3 result: #{step3.result}"
puts "Full chain inspect: #{step3.inspect}"
puts

puts "=" * 60
puts "Key Features:"
puts "  - Each method call makes an immediate API request"
puts "  - Previous result is passed as context to next call"
puts "  - Magic instances are immutable (functional style)"
puts "  - Auto-executes on puts/string interpolation via to_s"
puts "  - Access raw result via .result method"
puts "  - View chain history via .inspect method"
puts "=" * 60
