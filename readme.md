# 🪄 Magic

## Setup

1. Set `OPENAI_API_KEY` to a valid openai key
2. Install ruby `>= ruby 3.3.4`

## About

- Magic let's us call any function you can imagine.
- Magic methods can be chained together.
- If the method is called without a name it becomes anonymous.

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

...

### Recursion

...

## References

- [OpenAI API](https://platform.openai.com/docs/guides/text)
