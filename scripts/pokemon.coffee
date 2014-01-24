# Description:
#   Pokémon battles!
#
# Commands:
#   hubot fight me <pokemon> against <pokemon> - Makes the two pokemon fight each other. The winner is decided on type matches, total stat values, and a bit of randomness.

fs = require 'fs'

pokemons = JSON.parse fs.readFileSync('pokemonjson/pokemon.json').toString()
typechart = JSON.parse fs.readFileSync('pokemonjson/types.json').toString()

capitaliseFirstLetter = (string) ->
  return string.charAt(0).toUpperCase() + string.slice(1);

module.exports = (robot) ->
  robot.respond /fight m[ey] ([A-Za-z]+) against (@[A-Za-z0-9]+)?('s )?([A-Za-z]+)/i, (msg) ->
    fightMe msg, msg.match[1], msg.match[4], msg.match[2], (resp) ->
      msg.send resp

fightMe = (msg, pokemon1, pokemon2, opponent, cb) ->
  poke1 = (item for item in pokemons when item.name is capitaliseFirstLetter(pokemon1))[0]
  poke2 = (item for item in pokemons when item.name is capitaliseFirstLetter(pokemon2))[0]
  statTotal1 = +poke1.stats.hp + +poke1.stats.attack + +poke1.stats.defense + +poke1.stats.spattack + +poke1.stats.spdefense + +poke1.stats.speed
  statTotal2 = +poke2.stats.hp + +poke2.stats.attack + +poke2.stats.defense + +poke2.stats.spattack + +poke2.stats.spdefense + +poke2.stats.speed
  matchups1 = [];
  matchups2 = [];
  matchups1.push typechart[i1][i2] for i1 in poke1.type for i2 in poke2.type
  matchups2.push typechart[i2][i1] for i1 in poke1.type for i2 in poke2.type
  multiplier1 = matchups1.reduce ((x, y) -> x * y), 1
  multiplier2 = matchups2.reduce ((x, y) -> x * y), 1
  total1 = (statTotal1 * multiplier1) * (Math.random() * 0.2 + 0.9)
  total2 = (statTotal2 * multiplier2) * (Math.random() * 0.2 + 0.9)
  total1 = total1.toFixed(1)
  total2 = total2.toFixed(1)
  opponentStr = "your opponent"
  if(opponent)
    opponentStr = opponent
  if(+total1 > +total2)
    cb ("The winner is your " + poke1.name + ", with a total of " + total1 + " points against " + opponentStr + " pokemon " + poke2.name + "'s total of " + total2 + " points!")
  else if(+total2 > +total1)
    cb ("The winner is " + opponentStr + "'s " + poke2.name + ", with a total of " + total2 + " points against " + poke1.name + "'s total of " + total1 + " points!")
  else
    cb ("Both pokémon tied at " + total1 + " points!")

