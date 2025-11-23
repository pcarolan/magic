require 'minitest/autorun'
require_relative 'magic'
require 'json'

# Helper module to reduce HTTP mocking duplication
module HTTPMockHelpers
  def mock_http_response(code: '200', body: '{}')
    mock_response = Minitest::Mock.new
    
    # Handle multiple calls to code and body for error scenarios
    if code.to_i >= 400
      mock_response.expect :code, code
      mock_response.expect :code, code
      mock_response.expect :body, body
      mock_response.expect :body, body
    else
      mock_response.expect :code, code
      mock_response.expect :body, body
    end
    
    mock_response
  end

  def stub_http_request(mock_response, &block)
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
    }, &block
  end

  def mock_openai_response(text: '{"result": "test"}', status: '200')
    {
      status: status,
      body: {
        'output' => [
          {
            'content' => [
              {
                'text' => text
              }
            ]
          }
        ]
      }
    }
  end
end

class TestOpenAIClient < Minitest::Test
  include HTTPMockHelpers

  # Test constants
  DEFAULT_MODEL = 'gpt-5.1'
  TEST_API_KEY = 'test_api_key_12345'
  TEST_INPUT = 'test input'

  def setup
    @client = OpenAIClient.new(TEST_API_KEY)
  end

  def teardown
    ENV.delete('OPENAI_API_KEY') if ENV['OPENAI_API_KEY']&.include?('test')
  end

  # === Initialization Tests ===

  def test_initialize_with_explicit_api_key
    client = OpenAIClient.new(TEST_API_KEY)
    assert_equal TEST_API_KEY, client.instance_variable_get(:@api_key)
  end

  def test_initialize_with_env_variable
    ENV['OPENAI_API_KEY'] = 'env_test_key'
    client = OpenAIClient.new
    assert_equal 'env_test_key', client.instance_variable_get(:@api_key)
  ensure
    ENV.delete('OPENAI_API_KEY')
  end

  def test_initialize_with_nil_api_key
    client = OpenAIClient.new(nil)
    assert_nil client.instance_variable_get(:@api_key)
  end

  # === Success Response Tests ===

  def test_create_response_returns_hash_with_status_and_body
    mock_response = mock_http_response(
      code: '200',
      body: '{"output":[{"content":[{"text":"test response"}]}]}'
    )
    
    stub_http_request(mock_response) do
      result = @client.create_response(
        model: DEFAULT_MODEL,
        input: TEST_INPUT,
        max_output_tokens: 100,
        temperature: 0.7
      )
      
      assert_equal '200', result[:status]
      assert_kind_of Hash, result[:body]
      assert_includes result[:body].keys, 'output'
      assert_instance_of Array, result[:body]['output']
    end
  end

  def test_create_response_with_minimal_parameters
    mock_response = mock_http_response(
      code: '200',
      body: '{"output":[]}'
    )
    
    stub_http_request(mock_response) do
      result = @client.create_response(
        model: DEFAULT_MODEL,
        input: TEST_INPUT
      )
      
      assert_equal '200', result[:status]
      assert_kind_of Hash, result[:body]
    end
  end

  # === Error Response Tests ===

  def test_create_response_handles_json_parse_error
    # This scenario occurs when API returns non-JSON response
    mock_response = mock_http_response(
      code: '500',
      body: 'Internal Server Error'
    )
    
    stub_http_request(mock_response) do
      result = @client.create_response(
        model: DEFAULT_MODEL,
        input: TEST_INPUT
      )
      
      assert_equal '500', result[:status]
      assert_equal 'Internal Server Error', result[:body]
    end
  end

  def test_create_response_handles_401_unauthorized
    # Tests authentication failure
    mock_response = mock_http_response(
      code: '401',
      body: '{"error":{"message":"Invalid API key"}}'
    )
    
    stub_http_request(mock_response) do
      result = @client.create_response(
        model: DEFAULT_MODEL,
        input: TEST_INPUT
      )
      
      assert_equal '401', result[:status]
      assert_kind_of Hash, result[:body]
      assert_includes result[:body].keys, 'error'
    end
  end

  def test_create_response_handles_403_forbidden
    # Tests insufficient permissions
    mock_response = mock_http_response(
      code: '403',
      body: '{"error":{"message":"Forbidden"}}'
    )
    
    stub_http_request(mock_response) do
      result = @client.create_response(
        model: DEFAULT_MODEL,
        input: TEST_INPUT
      )
      
      assert_equal '403', result[:status]
    end
  end

  def test_create_response_handles_429_rate_limit
    # Tests rate limiting
    mock_response = mock_http_response(
      code: '429',
      body: '{"error":{"message":"Rate limit exceeded"}}'
    )
    
    stub_http_request(mock_response) do
      result = @client.create_response(
        model: DEFAULT_MODEL,
        input: TEST_INPUT
      )
      
      assert_equal '429', result[:status]
    end
  end

  def test_create_response_handles_502_bad_gateway
    # Tests server/proxy errors
    mock_response = mock_http_response(
      code: '502',
      body: 'Bad Gateway'
    )
    
    stub_http_request(mock_response) do
      result = @client.create_response(
        model: DEFAULT_MODEL,
        input: TEST_INPUT
      )
      
      assert_equal '502', result[:status]
      assert_equal 'Bad Gateway', result[:body]
    end
  end

  def test_create_response_handles_empty_response_body
    # Edge case: empty response from server (falls into JSON parse error path)
    mock_response = mock_http_response(
      code: '200',
      body: ''
    )
    
    # Empty string triggers JSON parse error, so we need extra expects
    mock_response.expect :code, '200'
    mock_response.expect :body, ''
    
    stub_http_request(mock_response) do
      result = @client.create_response(
        model: DEFAULT_MODEL,
        input: TEST_INPUT
      )
      
      assert_equal '200', result[:status]
      assert_equal '', result[:body]
    end
  end
end

class TestMagic < Minitest::Test
  include HTTPMockHelpers

  # Test constants
  DEFAULT_MODEL = 'gpt-5.1'
  DEFAULT_MAX_TOKENS = 1000
  DEFAULT_TEMPERATURE = 0.7

  def setup
    @magic = Magic.new
  end

  def teardown
    ENV.delete('DEBUG')
  end

  # === respond_to? Tests ===

  def test_magic_responds_to_any_method
    assert_respond_to @magic, :any_random_method
    assert_respond_to @magic, :get_stock_price
    assert_respond_to @magic, :state_capital
  end

  def test_respond_to_missing_returns_true
    # Explicitly test respond_to_missing? behavior
    assert @magic.respond_to?(:literally_anything)
    assert @magic.respond_to?(:undefined_method_name)
    assert @magic.respond_to?(:foo_bar_baz, true)
  end

  # === method_missing Tests ===

  def test_method_missing_calls_send_to_openai
    # Verify method_missing delegates to send_to_openai with correct structure
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

  def test_method_missing_with_no_arguments
    # Edge case: method called with no args
    @magic.define_singleton_method(:send_to_openai) do |input:|
      input
    end

    result = @magic.some_method
    assert_equal :some_method, result[:method_name]
    assert_equal [], result[:args]
  end

  def test_method_missing_with_nil_argument
    # Edge case: method called with nil
    @magic.define_singleton_method(:send_to_openai) do |input:|
      input
    end

    result = @magic.some_method(nil)
    assert_equal [nil], result[:args]
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

  def test_method_missing_with_mixed_arguments
    # Test positional + keyword + block
    @magic.define_singleton_method(:send_to_openai) do |input:|
      input
    end

    block = proc { "block" }
    result = @magic.complex_method('pos1', 'pos2', key1: 'val1', key2: 'val2', &block)
    
    assert_equal :complex_method, result[:method_name]
    assert_equal ['pos1', 'pos2', {key1: 'val1', key2: 'val2'}], result[:args]
    assert_equal block, result[:block]
  end

  # === send_to_openai Tests ===

  def test_send_to_openai_with_successful_response
    # Happy path: complete valid response
    mock_response = mock_openai_response(text: '{"result": "mocked response"}')
    
    mock_client = Minitest::Mock.new
    mock_client.expect :create_response, mock_response do |**kwargs|
      kwargs[:model] == DEFAULT_MODEL &&
      kwargs[:input].is_a?(String) &&
      kwargs[:max_output_tokens] == DEFAULT_MAX_TOKENS &&
      kwargs[:temperature] == DEFAULT_TEMPERATURE
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
    # Edge case: API returns incomplete response structure
    mock_response = {
      status: '200',
      body: {}
    }
    
    mock_client = Minitest::Mock.new
    mock_client.expect :create_response, mock_response do |**kwargs|
      kwargs[:model] == DEFAULT_MODEL &&
      kwargs[:input].is_a?(String) &&
      kwargs[:max_output_tokens] == DEFAULT_MAX_TOKENS &&
      kwargs[:temperature] == DEFAULT_TEMPERATURE
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

  def test_send_to_openai_handles_incomplete_output_structure
    # Edge case: output array exists but content is missing
    mock_response = {
      status: '200',
      body: {
        'output' => [{}]  # Missing content array
      }
    }
    
    mock_client = Minitest::Mock.new
    mock_client.expect :create_response, mock_response do |**kwargs|
      kwargs[:input].is_a?(String)
    end

    OpenAIClient.stub :new, mock_client do
      result = @magic.send_to_openai(input: {
        method_name: :test,
        args: [],
        block: nil
      })

      # Should gracefully return nil instead of crashing
      assert_nil result
    end

    mock_client.verify
  end

  def test_send_to_openai_handles_empty_output_array
    # Edge case: output array is empty
    mock_response = {
      status: '200',
      body: {
        'output' => []
      }
    }
    
    mock_client = Minitest::Mock.new
    mock_client.expect :create_response, mock_response do |**kwargs|
      kwargs[:input].is_a?(String)
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

  def test_send_to_openai_includes_prompt_in_input
    # Verify that MAIN_PROMPT is included in the request
    mock_response = mock_openai_response
    
    mock_client = Minitest::Mock.new
    mock_client.expect :create_response, mock_response do |**kwargs|
      kwargs[:input].include?('interpreter') &&
      kwargs[:input].include?('method_name')
    end

    OpenAIClient.stub :new, mock_client do
      @magic.send_to_openai(input: {
        method_name: :test,
        args: [],
        block: nil
      })
    end

    mock_client.verify
  end
end

class TestIntegration < Minitest::Test
  include HTTPMockHelpers

  def test_main_prompt_constant_exists
    assert defined?(MAIN_PROMPT)
    assert_kind_of String, MAIN_PROMPT
    assert_includes MAIN_PROMPT, 'interpreter'
    assert_includes MAIN_PROMPT, 'json'
  end

  def test_main_prompt_is_not_empty
    refute_empty MAIN_PROMPT
    assert MAIN_PROMPT.length > 10
  end

  def test_magic_and_openai_client_integration
    # End-to-end test: Magic -> OpenAIClient -> HTTP mock
    magic = Magic.new
    
    mock_response = mock_http_response(
      code: '200',
      body: JSON.generate({
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
    )
    
    stub_http_request(mock_response) do
      result = magic.meaning_of_life
      assert_equal '{"answer": 42}', result
    end
  end

  def test_integration_with_error_response
    # End-to-end test with API error (non-JSON response)
    magic = Magic.new
    
    mock_response = mock_http_response(
      code: '500',
      body: 'Server Error'
    )
    
    stub_http_request(mock_response) do
      # When response.body is a String (not Hash), should return nil gracefully
      result = magic.some_method
      assert_nil result
    end
  end

  def test_integration_with_real_method_call_pattern
    # Test a realistic use case
    magic = Magic.new
    
    mock_response = mock_http_response(
      code: '200',
      body: JSON.generate({
        'output' => [
          {
            'content' => [
              {
                'text' => '{"capital": "Lansing"}'
              }
            ]
          }
        ]
      })
    )
    
    stub_http_request(mock_response) do
      result = magic.state_capital('Michigan', 'USA')
      assert_equal '{"capital": "Lansing"}', result
    end
  end
end
