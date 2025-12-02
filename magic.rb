# Magic uses method_missing and an llm to return 
# the result of any method you can think of.

# standard library ONLY!
require 'net/http'
require 'json'
require 'uri'
require 'openssl'
require 'open3'
require 'time'


MAIN_PROMPT = <<-PROMPT
You are an interpreter that executes method calls.
Given a method name and arguments, return ONLY the direct answer.

CRITICAL: Your response must be ONLY the answer itself. 
- NO JSON
- NO metadata  
- NO labels like "quote:" or "answer:"
- NO wrapping of any kind
- Just the raw content

For example, if asked for a quote, respond with ONLY the quote text itself.

TOOL USAGE: If you need to execute a system command to answer the question, respond with: [TOOL:bash] command_here
After the tool executes, you will receive the output and should format it appropriately as your final answer.
PROMPT

class MagicLogger
  LOG_FILE = 'log.txt'
  
  def initialize(log_file: LOG_FILE)
    @log_file = log_file
    @mutex = Mutex.new
  end

  def log_request(request_id:, method_name:, args: [], model:, prompt_length:, max_tokens: nil, temperature: nil, tool_used: false, tool_command: nil)
    log_entry = {
      timestamp: Time.now.utc.iso8601,
      level: 'INFO',
      type: 'request',
      request_id: request_id,
      method_name: method_name,
      args: args.map(&:to_s),
      model: model,
      prompt_length: prompt_length,
      max_tokens: max_tokens,
      temperature: temperature,
      tool_used: tool_used,
      tool_command: tool_command
    }
    
    write_log(log_entry)
  end

  def log_response(request_id:, status:, response_length: nil, duration_ms: nil, error: nil, tool_executed: false)
    log_entry = {
      timestamp: Time.now.utc.iso8601,
      level: error ? 'ERROR' : 'INFO',
      type: 'response',
      request_id: request_id,
      status: status.to_s,
      response_length: response_length,
      duration_ms: duration_ms,
      error: error,
      tool_executed: tool_executed
    }
    
    write_log(log_entry)
  end

  def log_tool_execution(request_id:, command:, success:, output_length: nil, error: nil, duration_ms: nil)
    log_entry = {
      timestamp: Time.now.utc.iso8601,
      level: success ? 'INFO' : 'ERROR',
      type: 'tool_execution',
      request_id: request_id,
      command: command,
      success: success,
      output_length: output_length,
      error: error,
      duration_ms: duration_ms
    }
    
    write_log(log_entry)
  end

  private

  def write_log(log_entry)
    @mutex.synchronize do
      File.open(@log_file, 'a') do |f|
        f.puts(JSON.generate(log_entry))
        f.flush
      end
    end
  rescue => e
    # Silently fail logging to avoid breaking main functionality
    # Could optionally print to stderr in debug mode
    STDERR.puts("Logging error: #{e.message}") if ENV['DEBUG']
  end
end

class ToolExecutor
  DANGEROUS_COMMANDS = %w[
    rm sudo chmod chown dd mkfs fdisk shutdown reboot kill killall rmdir unlink
  ].freeze

  DANGEROUS_PATTERNS = [
    />/,           # Output redirection
    />>/,          # Append redirection
    /\|\s*(rm|sudo|chmod|chown|dd|mkfs|fdisk|shutdown|reboot|kill|killall|rmdir|unlink)/i  # Pipes to dangerous commands
  ].freeze

  def blacklisted?(command)
    return true if command.nil? || command.strip.empty?
    
    cmd_parts = command.strip.split(/\s+/)
    first_word = cmd_parts.first.downcase
    
    # Check against dangerous commands
    return true if DANGEROUS_COMMANDS.any? { |dangerous| first_word == dangerous }
    
    # Check against dangerous patterns
    return true if DANGEROUS_PATTERNS.any? { |pattern| command.match?(pattern) }
    
    false
  end

  def execute(command)
    return { success: false, output: '', error: 'Command is blacklisted for security reasons' } if blacklisted?(command)
    
    begin
      stdout, stderr, status = Open3.capture3(command)
      
      {
        success: status.success?,
        output: stdout,
        error: stderr
      }
    rescue => e
      {
        success: false,
        output: '',
        error: e.message
      }
    end
  end
end

class Magic
  def initialize(history: [], last_result: nil, logger: nil)
    @history = history
    @last_result = last_result
    @logger = logger || MagicLogger.new
  end

  def generate_request_id
    "#{Time.now.to_f}-#{rand(1000000)}"
  end

  def method_missing(method, *args, &block)
    # Prepare input hash
    input_hash = {
      method_name: method,
      args: args,
      previous_result: @last_result,  # Pass context from previous call
      block: block
    }
    
    # Execute immediately
    result = send_to_openai(input: input_hash)
    
    # Extract tool info if present
    tool_used = input_hash[:tool_used] || false
    tool_command = input_hash[:tool_command]
    
    # Print thinking step (intermediate result) unless in test mode
    unless ENV['MAGIC_TEST_MODE']
      step_number = @history.length + 1
      puts "\n🔮 Step #{step_number}: #{method}#{args.empty? ? '' : "(#{args.map(&:inspect).join(', ')})"}"
      puts "   → #{result.inspect}"
    end
    
    # Build new history entry
    history_entry = {
      method: method,
      args: args,
      block: block,
      result: result,
      tool_used: tool_used,
      tool_command: tool_command
    }
    
    new_history = @history + [history_entry]
    
    # Return new Magic instance for chaining (preserve logger)
    Magic.new(history: new_history, last_result: result, logger: @logger)
  end

  def respond_to_missing?(method_name, include_private = false)
    true
  end

  def send_to_openai(input:)
    # Generate request ID for correlation
    request_id = generate_request_id
    
    # Format args in a readable way
    args_str = input[:args].map { |a| a.is_a?(Hash) ? a.map { |k,v| "#{k}: #{v}" }.join(', ') : a.inspect }.join(', ')
    
    # Build the prompt
    prompt = MAIN_PROMPT + "\n\n"
    prompt += "Previous context: #{input[:previous_result]}\n\n" if input[:previous_result]
    prompt += "Method: #{input[:method_name]}"
    prompt += "(#{args_str})" unless input[:args].empty?
    
    puts prompt if ENV['DEBUG']
    
    # Log request
    @logger.log_request(
      request_id: request_id,
      method_name: input[:method_name],
      args: input[:args],
      model: 'gpt-5.1',
      prompt_length: prompt.length,
      max_tokens: 1000,
      temperature: 0.7
    )
    
    start_time = Time.now
    response = OpenAIClient.new(logger: @logger, request_id: request_id).create_response(
      model: 'gpt-5.1',
      input: prompt,
      max_output_tokens: 1000,
      temperature: 0.7
    )
    duration_ms = ((Time.now - start_time) * 1000).round(2)
    
    # Handle error responses where body is a String, not a Hash
    # Note: Response logging is handled by OpenAIClient.create_response
    if response[:body].is_a?(Hash)
      llm_response = response.dig(:body, 'output', 0, 'content', 0, 'text')
      
      return nil unless llm_response
      
      # Check if LLM wants to use a tool
      tool_match = llm_response.match(/\[TOOL:bash\]\s*(.+)/)
      
      if tool_match
        command = tool_match[1].strip
        executor = ToolExecutor.new
        
        # Log tool request
        @logger.log_request(
          request_id: request_id,
          method_name: input[:method_name],
          args: input[:args],
          model: 'gpt-5.1',
          prompt_length: prompt.length,
          max_tokens: 1000,
          temperature: 0.7,
          tool_used: true,
          tool_command: command
        )
        
        # Check if command is blacklisted
        if executor.blacklisted?(command)
          @logger.log_tool_execution(
            request_id: request_id,
            command: command,
            success: false,
            error: 'Command is blacklisted for security reasons'
          )
          return "Error: Command '#{command}' is blacklisted for security reasons."
        end
        
        # Print tool usage
        unless ENV['MAGIC_TEST_MODE']
          puts "🔧 Tool: bash | Command: #{command}"
        end
        
        # Execute the command
        tool_start_time = Time.now
        tool_result = executor.execute(command)
        tool_duration_ms = ((Time.now - tool_start_time) * 1000).round(2)
        
        # Log tool execution
        @logger.log_tool_execution(
          request_id: request_id,
          command: command,
          success: tool_result[:success],
          output_length: tool_result[:output] ? tool_result[:output].length : nil,
          error: tool_result[:error],
          duration_ms: tool_duration_ms
        )
        
        # Store tool info for history tracking
        input[:tool_used] = true
        input[:tool_command] = command
        input[:tool_result] = tool_result
        
        # Feed tool output back to LLM for formatting
        if tool_result[:success]
          format_prompt = "Tool output: #{tool_result[:output]}\n\nFormat this result appropriately as your final answer."
        else
          format_prompt = "Tool execution failed with error: #{tool_result[:error]}\n\nProvide an appropriate error message or alternative answer."
        end
        
        # Make second LLM call to format the tool output
        format_request_id = generate_request_id
        @logger.log_request(
          request_id: format_request_id,
          method_name: "#{input[:method_name]}_format",
          args: [],
          model: 'gpt-5.1',
          prompt_length: format_prompt.length,
          max_tokens: 1000,
          temperature: 0.7,
          tool_used: false
        )
        
        format_start_time = Time.now
        format_response = OpenAIClient.new(logger: @logger, request_id: format_request_id).create_response(
          model: 'gpt-5.1',
          input: format_prompt,
          max_output_tokens: 1000,
          temperature: 0.7
        )
        format_duration_ms = ((Time.now - format_start_time) * 1000).round(2)
        
        # Note: Response logging is handled by OpenAIClient.create_response
        if format_response[:body].is_a?(Hash)
          formatted_result = format_response.dig(:body, 'output', 0, 'content', 0, 'text')
          formatted_result || tool_result[:output]
        else
          nil
        end
      else
        # No tool usage, return response as-is
        llm_response
      end
    else
      # Note: Error response logging is handled by OpenAIClient.create_response
      nil
    end
  end

  # Auto-execute on string conversion
  def to_s
    @last_result.to_s
  end

  # Explicit result accessor
  def result
    @last_result
  end

  # Alias for result (for backwards compatibility)
  alias_method :value, :result

  # Print the result
  def render
    puts @last_result
    self  # Return self for chaining
  end

  # Alias for render
  alias_method :pretty, :render

  # For debugging - show chain history
  def inspect
    "#<Magic history=#{@history.length} steps, result=#{@last_result.inspect}>"
  end

  # Prevent Ruby from trying to convert Magic to an array
  # This is needed for puts to work correctly
  def to_ary
    nil
  end

end


class OpenAIClient
  def initialize(api_key = ENV['OPENAI_API_KEY'], logger: nil, request_id: nil)
    @api_key = api_key
    @logger = logger || MagicLogger.new
    @request_id = request_id || "#{Time.now.to_f}-#{rand(1000000)}"
  end

  def create_response(model:, input:, max_output_tokens: nil, temperature: nil)
    uri = URI('https://api.openai.com/v1/responses')
    
    # Create the HTTP object
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    # Configure SSL certificate store
    http.cert_store = OpenSSL::X509::Store.new
    http.cert_store.set_default_paths
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    
    # Create the request
    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{@api_key}"
    
    # Build request body
    body = {
      model: model,
      input: input
    }
    body[:max_output_tokens] = max_output_tokens if max_output_tokens
    body[:temperature] = temperature if temperature
    
    # Set the request body
    request.body = JSON.generate(body)
    
    # Make the request
    start_time = Time.now
    response = http.request(request)
    duration_ms = ((Time.now - start_time) * 1000).round(2)
    
    parsed_body = begin
      JSON.parse(response.body)
    rescue JSON::ParserError
      response.body
    end
    
    # Log HTTP response
    if parsed_body.is_a?(Hash)
      output_text = parsed_body.dig('output', 0, 'content', 0, 'text')
      @logger.log_response(
        request_id: @request_id,
        status: response.code,
        response_length: output_text ? output_text.length : nil,
        duration_ms: duration_ms
      )
    else
      @logger.log_response(
        request_id: @request_id,
        status: response.code,
        duration_ms: duration_ms,
        error: 'JSON parse error'
      )
    end
    
    {
      status: response.code,
      body: parsed_body
    }
  end
end
