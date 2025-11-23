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
You will find an answer.
You will return a response in valid json.
Message:
PROMPT

class Magic
  def method_missing(method, *args, &block)
    send_to_openai(input: {
      method_name: method || 'anonymous',
      args: args || [],
      block: block || nil
    })
  end

  def send_to_openai(input:)
    # Send the input to the openai api
    # and return the response
    prompt = MAIN_PROMPT + "\n" + input.to_s
    puts prompt
    OpenAIClient.new.create_response(
      model: 'gpt-5.1',
      input: MAIN_PROMPT + "\n" + input.to_s,
      max_output_tokens: 1000,
      temperature: 0.7
    ).dig(:body, 'output', 0, 'content', 0, 'text')
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
