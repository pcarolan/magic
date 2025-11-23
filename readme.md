# 🪄 Magic

## Setup

1. Set `OPENAI_API_KEY` to a valid openai key
2. Install ruby `>= ruby 3.3.4`
3. Run tests `ruby test_magic.rb` to make sure everything's working properly

## About

- Magic let's us call any function and get a pretty good answer.
- Magic methods can be chained together.
- If the method is called without a name it becomes anonymous.
- Magic methods are recursive

## Try it

```bash
> irb
irb(main):002> require_relative 'magic'
=> true
irb(main):003> magic = Magic.new
=> #<Magic:0x00000001204c8a30>
irb(main):004> magic.name_of_us_president_in_year('1994')
=> "{\"answer\":\"Bill Clinton\"}"
```

## Examples

### Single Method Calls

```ruby
magic = Magic.new

result = magic.random_number
puts "Result type: #{result.class}"
# => Result type: Magic
puts "Result value (via .to_s): #{result.to_s}"
# => Result value (via .to_s): 42
puts "Result value (via .result): #{result.result}"
# => Result value (via .result): 42

# Other examples:
magic.state_capital('Michigan', 'USA')
# => {"country":"USA","state":"Michigan","capital":"Lansing"}

magic.random_number_generator(0..100)
# => {"result": 57}

magic.types_of_cheese_in_geo('world')
# => {"answer":["Cheddar","Mozzarella","Parmesan","Gouda","Brie","Camembert","Swiss (Emmental)","Gruyère","Feta","Blue cheese (e.g., Roquefort, Gorgonzola, Stilton)","Monterey Jack","Colby","Provolone","Edam","Havarti","Manchego","Ricotta","Cottage cheese","Paneer","Halloumi","Queso fresco","Queso Oaxaca","Mascarpone","Pecorino Romano","Asiago","Stilton","Roquefort","Gorgonzola","Taleggio","Fontina","Muenster","Limburger","Chèvre (goat cheese)","Cotija","Requeijão","Serra da Estrela","Kashkaval","Suluguni","Nabulsi","Akkawi"]}

magic.types_of_cheese_in_geo('france')
# => {"country":"france","types_of_cheese":["Brie","Camembert","Roquefort","Comté","Reblochon","Munster","Pont-l’Évêque","Bleu d’Auvergne","Cantal","Saint-Nectaire","Tomme de Savoie","Chèvre (various goat cheeses such as Crottin de Chavignol, Valençay, Sainte-Maure de Touraine)"]}

```

### Method Chaining

Magic enables fluent API method chaining. Each method call makes an immediate API request and passes the previous result as context to the next call.

#### Example 1: Chaining Two Methods

```ruby
result = magic.random_number.multiply_by(5)
puts "Result type: #{result.class}"
# => Result type: Magic
puts "Chained result: #{result.to_s}"
# => Chained result: 210
puts "History length: #{result.instance_variable_get(:@history).length} steps"
# => History length: 2 steps
```

#### Example 2: Chaining Three Methods

```ruby
result = magic.random_number.multiply_by(5).add(10)
puts "Result: #{result}"  # Auto-calls to_s
# => Result: 220
puts "History: #{result.inspect}"
# => History: #<Magic history=3 steps, result="220">
```

#### Example 3: Accessing Intermediate Results

```ruby
step1 = magic.get_number
puts "Step 1 result: #{step1.result}"
# => Step 1 result: 42

step2 = step1.double_it
puts "Step 2 result: #{step2.result}"
# => Step 2 result: 84

step3 = step2.add(100)
puts "Step 3 result: #{step3.result}"
# => Step 3 result: 184
puts "Full chain inspect: #{step3.inspect}"
# => Full chain inspect: #<Magic history=3 steps, result="184">
```

#### Key Features:

- Each method call makes an immediate API request
- Previous result is passed as context to next call
- Magic instances are immutable (functional style)
- Auto-executes on `puts`/string interpolation via `to_s`
- Access raw result via `.result` method
- View chain history via `.inspect` method

### Recursion

Magic supports recursive operations through its context-aware chaining. Each method call receives the previous result as context, enabling the LLM to reason recursively about nested data structures.

#### Example 1: Recursive Data Processing

```ruby
# Start with a list and recursively process it
result = magic.list_us_presidents
  .take_first(5)
  .get_birthplaces
  .find_common_state

# Each step:
# 1. list_us_presidents → Returns list of presidents
# 2. take_first(5) → Takes first 5 (receives previous list as context)
# 3. get_birthplaces → Extracts birthplaces (receives filtered list)
# 4. find_common_state → Finds most common state (receives birthplace data)

puts result
# => {"most_common_state": "Virginia", "count": 8}
```

#### Example 2: Nested Object Navigation

```ruby
# Navigate through nested data structures recursively
result = magic.countries_in('Europe')
  .get_details('France')
  .largest_city
  .population

# The LLM recursively drills down:
# Europe → France → Paris → Population
puts result
# => {"city": "Paris", "population": 2165423}
```

#### Example 3: Recursive Computation

```ruby
# Mathematical recursion through chaining
result = magic.factorial(5)
  .multiply_by(2)
  .add(10)

# 5! = 120 → 120 * 2 = 240 → 240 + 10 = 250
puts result
# => {"result": 250}
```

#### Example 4: Self-Referential Operations

```ruby
# Each call can reference its own previous result
result = magic.number(10)
  .double_it      # 10 * 2 = 20
  .add_previous   # 20 + 10 = 30 (LLM can reference original)
  .square         # 30^2 = 900

puts result
# => {"result": 900}
```

#### How Recursion Works

Magic's recursion differs from traditional function recursion:

1. **Context Passing**: Each chained call receives the previous result in the prompt:

   ```ruby
   # Previous result is automatically included
   "Previous result: {previous_value}"
   ```

2. **Chain History**: The `@history` array maintains a complete audit trail of all operations

3. **LLM Reasoning**: The LLM can recursively reason about nested structures since it has access to context

4. **Sequential Execution**: Unlike traditional recursion (function calling itself), Magic's recursion is:
   - **Sequential**: Each step executes and passes results forward
   - **Context-aware**: The LLM has access to previous results
   - **Implicit**: You don't write recursive functions; chaining creates recursive behavior
   - **LLM-powered**: Intelligence comes from the LLM understanding nested structures

This makes Magic particularly powerful for exploratory data navigation where you don't know the exact structure ahead of time!

## References

- [OpenAI API](https://platform.openai.com/docs/guides/text)
