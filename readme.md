# 🪄 Magic

## Setup

1. Set `OPENAI_API_KEY` to a valid openai key
2. Install ruby `>= ruby 3.3.4`

## About

- Magic let's us call any function you can imagine.
- Magic methods can be chained together.
- If the method is called without a name it becomes anonymous.

Examples:

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

## Prompt

System:

    You are an interpreter.
    You will receive a method_name and parameters.
    You will find an answer.
    You will return a response in json_form in the return type given in `return_type`.

## Roadmap

- [ ] Strong typing

## References

- [OpenAI API](https://platform.openai.com/docs/guides/text)

## Message Passing

Simple Explanation with Picture
ruby
a = "test123"

a.reverse # => '321tset'
Look closely at the colours\*\*.

Summary with a diagram
![alt text](https://i.sstatic.net/uOGv0.png)

Example of Usage:

Someone might say:

The reverse method is "called" on a.

What does it mean: let's break it down:

What is the message?
"reverse" is the message. you can think of messages as basically methods.
What is the receiver?
The string a is the receiver of the message.
What is the sender?
And the sender is the object where all of this is called. in this case, the object is self, which is main.
\*\* (my condolences if you are unable to see the colours. Notice carefully: black vs blue vs red.):

Prologue: "Inovking" Methods
I very much dislike the use of expressions e.g. "invoking methods on on objects". This might be confusing ¯\(ツ)/¯ , especially if English is not your native language. What does it mean?
