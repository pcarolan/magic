# Magic uses method_missing and an llm to return 
# the result of any method you can think of.

# standard library ONLY!
require 'net/http'
require 'json'
require 'uri'
require 'openssl'


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
PROMPT

class Magic
  def initialize(history: [], last_result: nil)
    @history = history
    @last_result = last_result
  end

  def method_missing(method, *args, &block)
    # Execute immediately
    result = send_to_openai(input: {
      method_name: method,
      args: args,
      previous_result: @last_result,  # Pass context from previous call
      block: block
    })
    
    # Print thinking step (intermediate result) unless in test mode
    unless ENV['MAGIC_TEST_MODE']
      step_number = @history.length + 1
      puts "\n🔮 Step #{step_number}: #{method}#{args.empty? ? '' : "(#{args.map(&:inspect).join(', ')})"}"
      puts "   → #{result.inspect}"
    end
    
    # Build new history entry
    new_history = @history + [{
      method: method,
      args: args,
      block: block,
      result: result
    }]
    
    # Return new Magic instance for chaining
    Magic.new(history: new_history, last_result: result)
  end

  def respond_to_missing?(method_name, include_private = false)
    true
  end

  def send_to_openai(input:)
    # Format args in a readable way
    args_str = input[:args].map { |a| a.is_a?(Hash) ? a.map { |k,v| "#{k}: #{v}" }.join(', ') : a.inspect }.join(', ')
    
    # Build the prompt
    prompt = MAIN_PROMPT + "\n\n"
    prompt += "Previous context: #{input[:previous_result]}\n\n" if input[:previous_result]
    prompt += "Method: #{input[:method_name]}"
    prompt += "(#{args_str})" unless input[:args].empty?
    
    puts prompt if ENV['DEBUG']
    response = OpenAIClient.new.create_response(
      model: 'gpt-5.1',
      input: prompt,
      max_output_tokens: 1000,
      temperature: 0.7
    )
    
    # Handle error responses where body is a String, not a Hash
    return nil unless response[:body].is_a?(Hash)
    
    response.dig(:body, 'output', 0, 'content', 0, 'text')
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
  def initialize(api_key = ENV['OPENAI_API_KEY'])
    @api_key = api_key
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
    response = http.request(request)
    
    {
      status: response.code,
      body: JSON.parse(response.body)
    }
  rescue JSON::ParserError
    {
      status: response.code,
      body: response.body
    }
  end
end
