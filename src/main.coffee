fs = require 'fs'
{MarkovModel, Generator} = require './model.coffee'

fs.readFile 'corpus.json', (err, data) ->
  corpus = JSON.parse data.toString()

  model = new MarkovModel(3)
  model.dict = JSON.parse fs.readFileSync('data.json').toString()

  ###

  for noteString, i in corpus
    console.log 'feeding string', i, 'of', corpus.length
    # Document separator
    model.feed '<end>'
    model.feed '<end>'
    model.feed '<begin>'
    model.feed '<begin>'

    for note in noteString
      if note.match(/undefined/)?
        console.log noteString
        exit 0
      model.feed note

  fs.writeFile 'data.json', JSON.stringify model.dict, null, 2
  ###

  console.log 'loaded'

  generator = new Generator model

  console.log 'created generator'

  arr = []
  for [1..100]
    arr = arr.concat(generator.getNext()).concat(['z'])
    #if (note.match(/[a-zA-Zr]/) ? 'r')[0].toLowerCase() is 'c' and Math.random() < 0.3
    #else
  console.log arr.join ' '
