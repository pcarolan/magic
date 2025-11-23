require 'minitest/autorun'
require_relative 'magic'
require 'json'

class TestOpenAIClient < Minitest::Test
  def setup
    @client = OpenAIClient.new('test_api_key')
  end

  def test_initialize_with_api_key
    assert_equal 'test_api_key', @client.instance_variable_get(:@api_key)
  end

  def test_initialize_with_env_variable
    ENV['OPENAI_API_KEY'] = 'env_test_key'
    client = OpenAIClient.new
    assert_equal 'env_test_key', client.instance_variable_get(:@api_key)
  ensure
    ENV.delete('OPENAI_API_KEY')
  end

  def test_create_response_returns_hash_with_status_and_body
    # Mock the HTTP request
    mock_response = Minitest::Mock.new
    mock_response.expect :code, '200'
    mock_response.expect :body, '{"output":[{"content":[{"text":"test response"}]}]}'
    
    mock_cert_store = Minitest::Mock.new
    mock_cert_store.expect :set_default_paths, nil
    
    Net::HTTP.stub :new, ->(*args) {
      mock_http = Minitest::Mock.new
      mock_http.expect :use_ssl=, nil, [true]
      mock_http.expect :cert_store=, nil, [Object]
      mock_http.expect :cert_store, mock_cert_store
      mock_http.expect :verify_mode=, nil, [Integer]
      mock_http.expect :request, mock_response, [Object]
      mock_http
    } do
      result = @client.create_response(
        model: 'gpt-5.1',
        input: 'test input',
        max_output_tokens: 100,
        temperature: 0.7
      )
      
      assert_equal '200', result[:status]
      assert_kind_of Hash, result[:body]
      assert result[:body].key?('output')
    end
  end

  def test_create_response_handles_json_parse_error
    # Mock the HTTP request with invalid JSON
    mock_response = Minitest::Mock.new
    mock_response.expect :code, '500' # Called in the rescue block
    mock_response.expect :code, '500' # Called in the return hash
    mock_response.expect :body, 'invalid json' # Called in JSON.parse
    mock_response.expect :body, 'invalid json' # Called in return hash
    
    mock_cert_store = Minitest::Mock.new
    mock_cert_store.expect :set_default_paths, nil
    
    Net::HTTP.stub :new, ->(*args) {
      mock_http = Minitest::Mock.new
      mock_http.expect :use_ssl=, nil, [true]
      mock_http.expect :cert_store=, nil, [Object]
      mock_http.expect :cert_store, mock_cert_store
      mock_http.expect :verify_mode=, nil, [Integer]
      mock_http.expect :request, mock_response, [Object]
      mock_http
    } do
      result = @client.create_response(
        model: 'gpt-5.1',
        input: 'test input'
      )
      
      assert_equal '500', result[:status]
      assert_equal 'invalid json', result[:body]
    end
  end
end

class TestMagic < Minitest::Test
  def setup
    @magic = Magic.new
  end

  def test_magic_responds_to_any_method
    assert_respond_to @magic, :any_random_method
    assert_respond_to @magic, :get_stock_price
    assert_respond_to @magic, :state_capital
  end

  def test_method_missing_calls_send_to_openai
    # Mock the send_to_openai method
    @magic.define_singleton_method(:send_to_openai) do |input:|
      {
        method_name: input[:method_name],
        args: input[:args],
        received: true
      }
    end

    result = @magic.test_method('arg1', 'arg2')
    assert result[:received]
    assert_equal :test_method, result[:method_name]
    assert_equal ['arg1', 'arg2'], result[:args]
  end

  def test_send_to_openai_with_mocked_api
    # Mock the entire API response chain
    mock_response = {
      status: '200',
      body: {
        'output' => [
          {
            'content' => [
              {
                'text' => '{"result": "mocked response"}'
              }
            ]
          }
        ]
      }
    }
    
    mock_client = Minitest::Mock.new
    mock_client.expect :create_response, mock_response do |**kwargs|
      kwargs[:model] == 'gpt-5.1' &&
      kwargs[:input].is_a?(String) &&
      kwargs[:max_output_tokens] == 1000 &&
      kwargs[:temperature] == 0.7
    end

    OpenAIClient.stub :new, mock_client do
      result = @magic.send_to_openai(input: {
        method_name: :test,
        args: [],
        block: nil
      })

      assert_equal '{"result": "mocked response"}', result
    end

    mock_client.verify
  end

  def test_send_to_openai_handles_nil_response
    # Mock API returning nil in the dig chain
    mock_response = {
      status: '200',
      body: {}
    }
    
    mock_client = Minitest::Mock.new
    mock_client.expect :create_response, mock_response do |**kwargs|
      kwargs[:model] == 'gpt-5.1' &&
      kwargs[:input].is_a?(String) &&
      kwargs[:max_output_tokens] == 1000 &&
      kwargs[:temperature] == 0.7
    end

    OpenAIClient.stub :new, mock_client do
      result = @magic.send_to_openai(input: {
        method_name: :test,
        args: [],
        block: nil
      })

      assert_nil result
    end

    mock_client.verify
  end

  def test_method_missing_with_block
    @magic.define_singleton_method(:send_to_openai) do |input:|
      input
    end

    block_passed = proc { "test block" }
    result = @magic.some_method(&block_passed)
    
    assert_equal :some_method, result[:method_name]
    assert_equal block_passed, result[:block]
  end

  def test_method_missing_with_keyword_arguments
    @magic.define_singleton_method(:send_to_openai) do |input:|
      input
    end

    result = @magic.get_stock_price('GOOGL', as_of_date: '2025-11-20')
    
    assert_equal :get_stock_price, result[:method_name]
    assert_equal ['GOOGL', {as_of_date: '2025-11-20'}], result[:args]
  end
end

class TestIntegration < Minitest::Test
  def test_main_prompt_constant_exists
    assert defined?(MAIN_PROMPT)
    assert_kind_of String, MAIN_PROMPT
    assert_includes MAIN_PROMPT, 'interpreter'
  end

  def test_magic_and_openai_client_integration
    magic = Magic.new
    
    # Mock the entire HTTP stack
    mock_response = Minitest::Mock.new
    mock_response.expect :code, '200'
    mock_response.expect :body, JSON.generate({
      'output' => [
        {
          'content' => [
            {
              'text' => '{"answer": 42}'
            }
          ]
        }
      ]
    })
    
    mock_cert_store = Minitest::Mock.new
    mock_cert_store.expect :set_default_paths, nil
    
    Net::HTTP.stub :new, ->(*args) {
      mock_http = Minitest::Mock.new
      mock_http.expect :use_ssl=, nil, [true]
      mock_http.expect :cert_store=, nil, [Object]
      mock_http.expect :cert_store, mock_cert_store
      mock_http.expect :verify_mode=, nil, [Integer]
      mock_http.expect :request, mock_response, [Object]
      mock_http
    } do
      result = magic.meaning_of_life
      assert_equal '{"answer": 42}', result
    end
  end
end
