# Magic uses method_missing and an llm to return 
# the result of any method you can think of.

# standard library ONLY!
require 'net/http'
require 'json'
require 'uri'
require 'openssl'


MAIN_PROMPT = <<-PROMPT

You are an interpreter.
You will receive a method_name and arguments (:args).
If a previous_result is provided, use it as context for the current operation.
You will find an answer.
You will return a response in valid json.
Message:
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
    
    # Print thinking step (intermediate result) in debug mode
    if ENV['DEBUG']
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
    # Send the input to the openai api
    # and return the response
    prompt = if input[:previous_result]
      MAIN_PROMPT + "\nPrevious result: #{input[:previous_result]}\n" + input.to_json
    else
      MAIN_PROMPT + "\n" + input.to_json
    end
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
