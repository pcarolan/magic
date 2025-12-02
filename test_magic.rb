require 'minitest/autorun'
require_relative 'magic'
require 'json'

# Suppress thinking output during tests
ENV['MAGIC_TEST_MODE'] = 'true'

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
    # Verify method_missing executes and returns Magic instance
    mock_response = mock_openai_response(text: 'test result')
    
    mock_client = Minitest::Mock.new
    mock_client.expect :create_response, mock_response do |**kwargs|
      kwargs[:input].include?('test_method') &&
      kwargs[:input].include?('arg1') &&
      kwargs[:input].include?('arg2')
    end

    OpenAIClient.stub :new, mock_client do
      result = @magic.test_method('arg1', 'arg2')
      assert_instance_of Magic, result
      assert_equal 'test result', result.to_s
    end

    mock_client.verify
  end

  def test_method_missing_with_no_arguments
    # Edge case: method called with no args
    mock_response = mock_openai_response(text: 'no args result')
    
    mock_client = Minitest::Mock.new
    mock_client.expect :create_response, mock_response do |**kwargs|
      kwargs[:input].include?('Method: some_method')
    end

    OpenAIClient.stub :new, mock_client do
      result = @magic.some_method
      assert_instance_of Magic, result
      assert_equal 'no args result', result.to_s
    end

    mock_client.verify
  end

  def test_method_missing_with_nil_argument
    # Edge case: method called with nil
    mock_response = mock_openai_response(text: 'nil arg result')
    
    mock_client = Minitest::Mock.new
    mock_client.expect :create_response, mock_response do |**kwargs|
      kwargs[:input].include?('Method: some_method(nil)')
    end

    OpenAIClient.stub :new, mock_client do
      result = @magic.some_method(nil)
      assert_instance_of Magic, result
    end

    mock_client.verify
  end

  def test_method_missing_with_block
    # Test that blocks are captured (even though they're not sent to API)
    mock_response = mock_openai_response(text: 'block result')
    
    mock_client = Minitest::Mock.new
    mock_client.expect :create_response, mock_response do |**kwargs|
      kwargs[:input].include?('some_method')
    end

    OpenAIClient.stub :new, mock_client do
      block_passed = proc { "test block" }
      result = @magic.some_method(&block_passed)
      
      assert_instance_of Magic, result
      # Verify block was captured in history
      assert_equal block_passed, result.instance_variable_get(:@history)[0][:block]
    end

    mock_client.verify
  end

  def test_method_missing_with_keyword_arguments
    mock_response = mock_openai_response(text: '$150.00')
    
    mock_client = Minitest::Mock.new
    mock_client.expect :create_response, mock_response do |**kwargs|
      kwargs[:input].include?('get_stock_price') &&
      kwargs[:input].include?('GOOGL') &&
      kwargs[:input].include?('as_of_date')
    end

    OpenAIClient.stub :new, mock_client do
      result = @magic.get_stock_price('GOOGL', as_of_date: '2025-11-20')
      
      assert_instance_of Magic, result
      # Verify args were captured correctly in history
      assert_equal ['GOOGL', {as_of_date: '2025-11-20'}], result.instance_variable_get(:@history)[0][:args]
    end

    mock_client.verify
  end

  def test_method_missing_with_mixed_arguments
    # Test positional + keyword + block
    mock_response = mock_openai_response(text: 'complex result')
    
    mock_client = Minitest::Mock.new
    mock_client.expect :create_response, mock_response do |**kwargs|
      kwargs[:input].include?('complex_method') &&
      kwargs[:input].include?('pos1') &&
      kwargs[:input].include?('key1')
    end

    OpenAIClient.stub :new, mock_client do
      block = proc { "block" }
      result = @magic.complex_method('pos1', 'pos2', key1: 'val1', key2: 'val2', &block)
      
      assert_instance_of Magic, result
      history = result.instance_variable_get(:@history)[0]
      assert_equal ['pos1', 'pos2', {key1: 'val1', key2: 'val2'}], history[:args]
      assert_equal block, history[:block]
    end

    mock_client.verify
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
      kwargs[:input].include?('Method: test')
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

  # === Chaining Tests ===

  def test_method_missing_returns_magic_instance
    # Verify that method_missing returns a Magic instance for chaining
    mock_response = mock_openai_response(text: '42')
    
    mock_client = Minitest::Mock.new
    mock_client.expect :create_response, mock_response do |**kwargs|
      kwargs[:input].is_a?(String)
    end

    OpenAIClient.stub :new, mock_client do
      result = @magic.random_number
      assert_instance_of Magic, result
    end

    mock_client.verify
  end

  def test_chaining_two_methods
    # Test chaining two method calls
    first_response = mock_openai_response(text: '10')
    second_response = mock_openai_response(text: '50')
    
    call_count = 0
    mock_client = Minitest::Mock.new
    
    # First call
    mock_client.expect :create_response, first_response do |**kwargs|
      call_count += 1
      call_count == 1 &&
      kwargs[:input].is_a?(String) &&
      !kwargs[:input].include?('Previous context')
    end
    
    # Second call - should include previous result
    mock_client.expect :create_response, second_response do |**kwargs|
      call_count += 1
      call_count == 2 &&
      kwargs[:input].include?('Previous context: 10')
    end

    OpenAIClient.stub :new, mock_client do
      result = @magic.random_number.multiply_by(5)
      
      assert_instance_of Magic, result
      assert_equal '50', result.to_s
    end

    mock_client.verify
  end

  def test_chaining_three_methods
    # Test chaining three method calls
    responses = [
      mock_openai_response(text: '10'),
      mock_openai_response(text: '50'),
      mock_openai_response(text: '60')
    ]
    
    call_count = 0
    mock_client = Minitest::Mock.new
    
    # Set up expectations for all three calls
    3.times do |i|
      mock_client.expect :create_response, responses[i] do |**kwargs|
        call_count += 1
        true
      end
    end

    OpenAIClient.stub :new, mock_client do
      result = @magic.random_number.multiply_by(5).add(10)
      
      assert_instance_of Magic, result
      assert_equal '60', result.to_s
    end

    mock_client.verify
  end

  def test_chaining_passes_previous_result_as_context
    # Verify that previous result is passed as context in chained calls
    first_response = mock_openai_response(text: '{"number": 42}')
    second_response = mock_openai_response(text: '{"doubled": 84}')
    
    mock_client = Minitest::Mock.new
    
    # First call - no previous result
    mock_client.expect :create_response, first_response do |**kwargs|
      !kwargs[:input].include?('Previous context')
    end
    
    # Second call - should have previous result
    mock_client.expect :create_response, second_response do |**kwargs|
      kwargs[:input].include?('Previous context: {"number": 42}')
    end

    OpenAIClient.stub :new, mock_client do
      result = @magic.generate_number.double_it
      assert_equal '{"doubled": 84}', result.to_s
    end

    mock_client.verify
  end

  def test_result_method_returns_last_result
    # Test that .result method returns the last result
    mock_response = mock_openai_response(text: 'test result')
    
    mock_client = Minitest::Mock.new
    mock_client.expect :create_response, mock_response do |**kwargs|
      kwargs[:input].is_a?(String)
    end

    OpenAIClient.stub :new, mock_client do
      result = @magic.some_method
      assert_equal 'test result', result.result
    end

    mock_client.verify
  end

  def test_inspect_shows_history_length
    # Test that inspect shows chain history
    mock_response = mock_openai_response(text: 'result')
    
    mock_client = Minitest::Mock.new
    2.times do
      mock_client.expect :create_response, mock_response do |**kwargs|
        kwargs[:input].is_a?(String)
      end
    end

    OpenAIClient.stub :new, mock_client do
      result = @magic.first_method.second_method
      
      inspect_string = result.inspect
      assert_includes inspect_string, 'Magic'
      assert_includes inspect_string, 'history=2 steps'
    end

    mock_client.verify
  end

  def test_to_s_returns_string_representation
    # Test that to_s returns string representation of last result
    mock_response = mock_openai_response(text: '{"value": 123}')
    
    mock_client = Minitest::Mock.new
    mock_client.expect :create_response, mock_response do |**kwargs|
      kwargs[:input].is_a?(String)
    end

    OpenAIClient.stub :new, mock_client do
      result = @magic.get_value
      assert_equal '{"value": 123}', result.to_s
    end

    mock_client.verify
  end

  def test_new_magic_instance_has_empty_history
    # Test that a new Magic instance starts with empty history
    magic = Magic.new
    assert_equal [], magic.instance_variable_get(:@history)
    assert_nil magic.instance_variable_get(:@last_result)
  end

  def test_magic_with_initial_result
    # Test that Magic can be initialized with a result
    magic = Magic.new(last_result: 'initial value')
    assert_equal 'initial value', magic.result
  end
end

class TestIntegration < Minitest::Test
  include HTTPMockHelpers

  def test_main_prompt_constant_exists
    assert defined?(MAIN_PROMPT)
    assert_kind_of String, MAIN_PROMPT
    assert_includes MAIN_PROMPT, 'interpreter'
    assert_includes MAIN_PROMPT, 'answer'
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
      assert_equal '{"answer": 42}', result.to_s
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
      assert_instance_of Magic, result
      assert_nil result.result
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
      assert_equal '{"capital": "Lansing"}', result.to_s
    end
  end
end

class TestIRBSingleton < Minitest::Test
  include HTTPMockHelpers

  def setup
    # Clear any existing magic variable in TOPLEVEL_BINDING
    begin
      TOPLEVEL_BINDING.eval("magic = nil")
    rescue
      # Ignore if magic doesn't exist
    end
  end

  def teardown
    # Clean up
    begin
      TOPLEVEL_BINDING.eval("magic = nil")
    rescue
      # Ignore
    end
    ENV.delete('OPENAI_API_KEY') if ENV['OPENAI_API_KEY']&.include?('test')
  end

  def test_singleton_creation_in_toplevel_binding
    # Test that we can create magic singleton in TOPLEVEL_BINDING
    TOPLEVEL_BINDING.eval("magic = Magic.new")
    
    magic_instance = TOPLEVEL_BINDING.eval("magic")
    assert_instance_of Magic, magic_instance
  end

  def test_singleton_is_accessible_in_binding
    # Test that magic variable is accessible in a binding context
    binding_obj = binding
    binding_obj.eval("magic = Magic.new")
    
    magic_instance = binding_obj.eval("magic")
    assert_instance_of Magic, magic_instance
  end

  def test_singleton_can_call_methods
    # Test that the singleton magic instance can be used to call methods
    mock_response = mock_openai_response(text: 'test result')
    
    mock_client = Minitest::Mock.new
    mock_client.expect :create_response, mock_response do |**kwargs|
      kwargs[:input].include?('test_method')
    end

    binding_obj = binding
    binding_obj.eval("magic = Magic.new")

    OpenAIClient.stub :new, mock_client do
      result = binding_obj.eval("magic.test_method")
      assert_instance_of Magic, result
      assert_equal 'test result', result.to_s
    end

    mock_client.verify
  end

  def test_singleton_has_empty_history_initially
    # Test that singleton starts with empty history
    binding_obj = binding
    binding_obj.eval("magic = Magic.new")
    
    magic_instance = binding_obj.eval("magic")
    assert_equal [], magic_instance.instance_variable_get(:@history)
    assert_nil magic_instance.instance_variable_get(:@last_result)
  end

  def test_singleton_supports_chaining
    # Test that singleton supports method chaining
    responses = [
      mock_openai_response(text: '10'),
      mock_openai_response(text: '20')
    ]
    
    call_count = 0
    mock_client = Minitest::Mock.new
    
    2.times do |i|
      mock_client.expect :create_response, responses[i] do |**kwargs|
        call_count += 1
        true
      end
    end

    binding_obj = binding
    binding_obj.eval("magic = Magic.new")

    OpenAIClient.stub :new, mock_client do
      result = binding_obj.eval("magic.first_method.second_method")
      assert_instance_of Magic, result
      assert_equal '20', result.to_s
      # Verify history has 2 steps
      assert_equal 2, result.instance_variable_get(:@history).length
    end

    mock_client.verify
  end

  def test_irb_rc_hook_configuration
    # Test that IRB.conf[:IRB_RC] hook is set up correctly
    # This simulates what happens when IRB loads .irbrc
    begin
      require 'irb'
    rescue LoadError
      skip "IRB not available in test environment"
    end
    
    # Create a mock IRB context
    mock_context = Minitest::Mock.new
    mock_workspace = Minitest::Mock.new
    mock_binding = binding
    
    mock_workspace.expect :binding, mock_binding
    mock_context.expect :workspace, mock_workspace
    
    # Set up the IRB hook as done in .irbrc
    IRB.conf[:IRB_RC] = proc do |context|
      context.workspace.binding.eval("magic = Magic.new")
    end
    
    # Execute the hook
    IRB.conf[:IRB_RC].call(mock_context)
    
    # Verify magic was created in the binding
    magic_instance = mock_binding.eval("magic")
    assert_instance_of Magic, magic_instance
    
    mock_context.verify
    mock_workspace.verify
  end

  def test_singleton_independence
    # Test that each binding gets its own magic instance (they're independent)
    binding1 = binding
    binding2 = binding
    
    binding1.eval("magic = Magic.new")
    binding2.eval("magic = Magic.new")
    
    magic1 = binding1.eval("magic")
    magic2 = binding2.eval("magic")
    
    # They should be different instances
    refute_same magic1, magic2
    # But both should be Magic instances
    assert_instance_of Magic, magic1
    assert_instance_of Magic, magic2
  end
end
