require_relative 'magic'
require 'pp'

DEBUG = true

# Check if OpenAI API key is set
api_key_set = ENV['OPENAI_API_KEY'] && !ENV['OPENAI_API_KEY'].empty?
api_key_preview = api_key_set ? "#{ENV['OPENAI_API_KEY'][0..6]}..." : nil

# Create singleton magic instance and make it available in IRB session
# Use IRB hook to ensure it's available in the session
IRB.conf[:IRB_RC] = proc do |context|
  context.workspace.binding.eval("magic = Magic.new")
end

# Also set it in TOPLEVEL_BINDING as fallback
eval("magic = Magic.new", TOPLEVEL_BINDING)

puts "\e[1;36m🪄 Magic\e[0m is ready! Use \e[1;33mmagic\e[0m to get started"
if api_key_set
  puts "\e[1;32m✓\e[0m OpenAI API key configured (\e[2m#{api_key_preview}\e[0m)"
else
  puts "\e[1;31m⚠\e[0m  OpenAI API key not set (set \e[1mOPENAI_API_KEY\e[0m environment variable)"
end
puts "\e[2mDEBUG mode: #{DEBUG}\e[0m"
puts ""

# IRB Configuration
IRB.conf[:USE_COLORIZE] = true
IRB.conf[:PROMPT][:MY_PROMPT] = {
  PROMPT_I: "\e[1;32m>>\e[0m ",
  PROMPT_S: "\e[1;33m%l>\e[0m ",
  PROMPT_C: "\e[1;31m?>\e[0m ",
  PROMPT_N: "\e[1;34m?>\e[0m ",
  RETURN: "=> %s\n"
}
IRB.conf[:PROMPT_MODE] = :MY_PROMPT
IRB.conf[:INSPECT_MODE] = false
IRB.conf[:USE_MULTILINE] = true