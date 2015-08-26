# <HACK>
fs = require 'fs'
numeric = require 'numeric'

noteCorpus = []

shifts = {
  '#': 1
  '-': -1
  'a': 9
  'b': 11
  'c': 0
  'd': 2
  'e': 4
  'f': 5
  'g': 7
}

BASE = {
  'C': 48
  'D': 50
  'E': 52
  'F': 53
  'G': 55
  'A': 57
  'B': 59
  'c': 60
  'd': 62
  'e': 64
  'f': 65
  'g': 67
  'a': 69
  'b': 71
}

OCTAVES = {
  '\'': 12
  ',': -12
  '': 0
}

MODIFIER = {
  '^': 1
  '_': -1
  '': 0
}

exports.toMidi = toMidi = (note) ->
  return null unless note?
  noteMatch = note.match /([a-gA-Gz])(\'*\,*)(\^?\_?)/
  return BASE[noteMatch[1]] + OCTAVES[noteMatch[2][0] ? ''] * noteMatch[2].length + MODIFIER[noteMatch[3]]

abc = [
  ['c', '']
  ['d', '_']
  ['d', '']
  ['e', '_']
  ['e', '']
  ['f', '']
  ['g', '_']
  ['g', '']
  ['a', '_']
  ['a', '']
  ['b', '_']
  ['b', '']
]

fromMidi = (note) ->
  [base, modifier] = abc[note %% 12]
  octaves = (note // 12) - 5
  if octaves > 0
    return base + ('\'' for [0...octaves]).join('') + modifier
  else if octaves < 0
    return base + (',' for [0...-octaves]).join('') + modifier
  else
    return base + modifier

majorKeyNotes = [
  0, 2, 4, 5, 7, 9, 11
]

estimateKey = (string) ->
  histogram = (0 for [0...12])
  for note in string when note isnt '=' and not note.match(/z/)?
    tone = toMidi(note)
    for diff in majorKeyNotes
      histogram[tone - diff %% 12] += 1

  best = null; max = -Infinity
  for el, i in histogram
    if el > max
      best = i; max = el

  return best

normalizeKey = (string) ->
  key = estimateKey string
  result = []
  for note in string
    if note is '=' or note.match(/z/)
      result.push note
    else
      duration = note.match(/\/?\d+/)
      if duration?
        duration = duration[0]
      else
        duration = ''
      tone = toMidi(note)
      tone -= key
      result.push fromMidi(tone) + duration
  return result

loadNoteStrings = (kern) ->
  noteStrings = numeric.transpose(
    kern.split('\n').
         filter((x) -> x[..1] isnt '!!').
         map((x) -> x.split('\t'))
    ).filter((list) ->
      '**kern' in list
    ).map((list) ->
      list.filter((x) -> x?).
           filter((x) -> x not in ['.', '']).
           filter((x) -> x[0] not in ['!', '*', '='])
    )

  for string in noteStrings
    noteCorpus.push normalizeKey string.map((note) ->
      if note[0] is '='
        return '='
      else
        match = note.match(/\d*\.?[a-gA-Gr]+(?:[#-])?/)
        return match[0]
    ).map (note) ->
      if note is '='
        return '='
      else
        duration = note.match(/\d*/)[0]
        letterPitch = note.match(/[a-gA-Gr]+/)[0]
        modifier = note.match(/[#-]/)
        ###

        if letterPitch[0] is 'r'
          return duration + ':r'

        pitch = 48
        if letterPitch is letterPitch.toLowerCase()
          pitch += 12 * letterPitch.length
        else
          pitch -= 12 * (letterPitch.length - 1)

        pitch += shifts[letterPitch.toLowerCase()[0]]
        if modifier?
          pitch += shifts[modifier[0]]

        return duration + ':' + pitch

        ###
        if letterPitch[0] is 'r'
          abcPitch = 'z'
        else
          abcPitch = letterPitch[0] + ((if letterPitch[0] is letterPitch[0].toLowerCase() then '\'' else ',') for [1...letterPitch.length]).join('')
          if modifier?
            abcPitch += modifierTranslation[modifier[0]]
        duration = durationTranslation[duration] ? '/' + duration
        return abcPitch + duration

modifierTranslation = {'#': '^', '-': '_'}
durationTranslation = {
  '0': '2'
  '1': ''
  '2': '/2'
  '4': '/4'
  '8': '/8'
  '12': '/16'
  '32': '/32'
}

# </HACK>

EPSILON = -100
LAMBDA = 0.4

class Note
  constructor: (@duration, @pitch) ->

  toString: -> @duration + ':' + @pitch

class TokenListItem
  constructor: (@token) ->
    @next = null

class MarkovModel
  constructor: (@order) ->
    @last = ('<begin>' for [0...@order])
    @dict = {}

  feed: (token) ->
    @last.push token
    @last.shift()

    for i in [0...@order]
      key = @last[0...i].join('\t')
      @dict[key] ?= 0
      @dict[key] += 1

  getProbability: (list) ->
    key = list.join '\t'
    if key of @dict
      return Math.log(@dict[key]) - Math.log(@dict[''])
    else if list.length is 1
      return EPSILON
    else
      return @getProbability(list[...-1]) + @getProbability(list[1...])

  # TODO smoothing?

  getAlphabet: -> (key for key of @dict when (key.length > 0) and '\t' not in key)

class RawGenerator
  constructor: (@model) ->
    @last = ('<begin>' for [0...@model.order])
    @alphabet = @model.getAlphabet().filter (x) -> not x.match(/z|(32)|(16)|8/)? and x not in ['<begin>', '<end>']

  generate: ->
    probs = {}
    total = 0
    for token in @alphabet
      probs[token] = Math.E ** (@model.getProbability(@last.concat([token])) - @model.getProbability(@last))
      total += probs[token]

    barrier = Math.random() * total; total = 0
    for key, val of probs
      total += val
      if barrier < total
        @last.push key
        @last.shift()
        return key

class Generator
  constructor: (@model) ->
    preGenerator = new RawGenerator @model
    ###

    @personalModel = new MarkovModel @model.order
    for [0...200]
      @personalModel.feed preGenerator.generate()
    ###

    themeGenerator = preGenerator

    @thematicModel = new MarkovModel @model.order
    @theme = []; note = null
    until toMidi(note) %% 12 is 0
      note = themeGenerator.generate()
    @theme.push note
    @theme.push note = themeGenerator.generate()
    until toMidi(note) %% 12 is 0 and @theme.length > 5
      note = themeGenerator.generate()
      @theme.push note
      @thematicModel.feed note

    @thematicModel = new MarkovModel @model.order
    @response = []; note = null
    until toMidi(note) %% 12 is 0
      note = themeGenerator.generate()
    @response.push note
    @response.push note = themeGenerator.generate()
    until toMidi(note) %% 12 is 8 and @response.length > 5
      note = themeGenerator.generate()
      @response.push note
      @thematicModel.feed note

    @last = ('<begin>' for [0...@model.order])
    @alphabet = @model.getAlphabet().filter (x) -> not x.match(/z|(32)|(16)|8/)? and x not in ['<begin>', '<end>']

  generate: ->
    probs = {}
    total = 0
    for token in @alphabet
      probs[token] = Math.E ** (@model.getProbability(@last.concat([token])) - @model.getProbability(@last))
      total += probs[token]

    barrier = Math.random() * total; total = 0
    for key, val of probs
      total += val
      if barrier < total
        @last.push key
        @last.shift()
        return key

  riff: (excerpt) ->
    result = [excerpt[0]]
    for el, i in excerpt when i isnt 0 and i isnt excerpt.length - 1
      choice = Math.random()

      if choice < 0.1
        # Replace this with a similar note
        sublist = excerpt[i - 1..i + 1]
        probs = {}
        total = 0
        for token in @alphabet
          sublist[2] = token
          probs[token] = Math.E ** (@model.getProbability(sublist))
          total += probs[token]

        barrier = Math.random() * total; total = 0
        for key, val of probs
          total += val
          if barrier < total
            result.push key
            break
      else if choice < 0.2
        # Insert a new passing note
        sublist = [excerpt[i], null, excerpt[i + 1]]
        probs = {}
        total = 0
        for token in @alphabet
          sublist[2] = token
          probs[token] = Math.E ** (@model.getProbability(sublist))
          total += probs[token]

        barrier = Math.random() * total; total = 0
        for key, val of probs
          total += val
          if barrier < total
            result.push el
            result.push key
            break
      else if choice < 0.3
        # Combine with the previous note
        sublist = [result.pop(), null, excerpt[i]]
        probs = {}
        total = 0
        for token in @alphabet
          sublist[2] = token
          probs[token] = Math.E ** (@model.getProbability(sublist))
          total += probs[token]

        barrier = Math.random() * total; total = 0
        for key, val of probs
          total += val
          if barrier < total
            result.push key
            break
      else
        result.push el
    result.push excerpt[excerpt.length - 1]
    return result

  getNext: ->
    if @thematic
      @thematic = false
      return @theme
    else
      @thematic = true
      return @response

exports.MarkovModel = MarkovModel
exports.Generator = Generator
