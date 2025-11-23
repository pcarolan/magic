# Magic uses method_missing and an llm to return 
# the result of any method you can think of.

# standard library ONLY!
require 'net/http'
require 'json'
require 'uri'
require 'openssl'


class Magic
  def method_missing(method, *args, &block)
    {
        method_name: method,
        args: args,
        block: block
    }
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

# # Example usage:
# client = OpenAIClient.new
# result = client.create_response(
#   model: 'gpt-5.1',
#   input: 'Write a short bedtime story about a unicorn.',
#   max_output_tokens: 1000,
#   temperature: 0.7
# )

# if result[:status] == "200"
#   body = result[:body]
  
#   # Extract the text from the response
#   text = body.dig("output", 0, "content", 0, "text")
  
#   # Extract usage information
#   usage = body["usage"]
#   input_tokens = usage["input_tokens"]
#   output_tokens = usage["output_tokens"]
#   total_tokens = usage["total_tokens"]
  
#   # Print formatted output
#   puts "\n" + "="*80
#   puts "RESPONSE:"
#   puts "="*80
#   puts text
#   puts "\n" + "="*80
#   puts "TOKENS USED:"
#   puts "="*80
#   puts "  Input:  #{input_tokens}"
#   puts "  Output: #{output_tokens}"
#   puts "  Total:  #{total_tokens}"
#   puts "="*80 + "\n"
# else
#   puts "Error: Status #{result[:status]}"
#   puts result[:body]
# end


magic = Magic.new
result = magic.get_stock_price('GOOGL', as_of_date: '2025-11-20')
puts result
