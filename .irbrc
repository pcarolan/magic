require_relative 'magic'
require 'pp'

DEBUG = true
puts "DEBUG is set to #{DEBUG}"
puts "magic is ready 🪄, type magic = Magic.new to get started"

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