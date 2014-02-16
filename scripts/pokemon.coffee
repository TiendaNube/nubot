# Description:
#   Pokémon battles!
#
# Commands:
#   hubot fight [me] [@user's] <pokemon> against [@user's] <pokemon> - Simulates a pokemon battle.
#   hubot build me <pokemon> - Show the moves chosen for a given pokemon
#   hubot bulbapedia me <query> - Searches Bulbapedia for the given query

fs = require 'fs'

# Source: https://github.com/veekun/pokedex
pokemons = JSON.parse fs.readFileSync('pokemonjson/pokemon.json').toString()
movedex = JSON.parse fs.readFileSync('pokemonjson/moves.json').toString()

module.exports = (robot) ->
  robot.respond /fight (m[ey] )?((@[A-Za-z0-9]+)'s )?([A-Za-z .']+) against ((@[A-Za-z0-9]+)'s )?([A-Za-z .']+)/i, (msg) ->
    pkmn1 = new Pokemon msg.match[4], msg.match[3]
    pkmn2 = new Pokemon msg.match[7], msg.match[6] ? "the foe"
    battle = new Battle(pkmn1, pkmn2)
    msg.send battle.start()
  
  robot.respond /build me ([A-Za-z .]+)/i, (msg) ->
    pkmn = new Pokemon msg.match[1]
    moves = []
    for move in pkmn.moves
      moves.push(titleCase(move.name))
      
    msg.send moves.join("\n")
  
  robot.respond /bulbapedia me (.+)/i, (msg) ->
    msg.send 'http://bulbapedia.bulbagarden.net/w/index.php?search=' + msg.match[1]
  
  robot.error (err, msg) ->
    if msg?
      if err.message[..14] == 'PokemonNotFound'
        name = titleCase(err.message[16..])
        suggestions = (poke.name for poke in pokemons when (levenstein poke.name, name) < 3).join(', ')
        
        msg.send "No pokemon named " + name + "." + (if suggestions.length > 0 then " Did you mean " + suggestions + '?' else '')
      else
        msg.send err


# Assumes lv. 100 and all IVs at 31. Ignores EV and nature.
class Pokemon
  constructor: (name, trainer) ->
    pokedex = (item for item in pokemons when item.name is titleCase(name))[0]
    throw new Error("PokemonNotFound:" + name) unless pokedex?
    
    @name = pokedex.name
    @trainer = trainer
    @types = pokedex.type
    @multipliers = pokedex.damages
    
    @maxHp = 141 + 2 * pokedex.stats.hp
    @attack = this.statFormula pokedex.stats.attack
    @defense = this.statFormula pokedex.stats.defense
    @spattack = this.statFormula pokedex.stats.spattack
    @spdefense = this.statFormula pokedex.stats.spdefense
    @speed = this.statFormula pokedex.stats.speed
    
    @hp = @maxHp
    @moves = this.chooseMoves pokedex.moves
  
  trainerAndName: ->
    if not @trainer?
      return "your " + @name
    else
      return @trainer + "'s " + @name
    
  statFormula: (base) -> 36 + 2 * base
  
  chooseMoves: (pokedex) ->
    allMoves = pokedex.level.concat(pokedex.tmhm).concat(pokedex.egg).concat(pokedex.tutor)
    moves = []
    for movePointer in allMoves
      move = (item for item in movedex when item.name is movePointer.name)[0]
      continue unless move?
      
      continue if move.damage_class_id not in [2,3]
      # Effects that cause the move to take several turns or are otherwise problematic
      continue if move.effect_id in [8, 9, 27, 28, 39, 40, 76, 81, 146, 149, 152, 156, 159, 160, 191, 205, 230, 247, 249, 256, 257, 273, 293, 298, 312, 332, 333]
      
      # Effects that could be implemented more easily, such as multi-hit attacks or recoil
      continue if move.effect_id in [30, 45, 46, 49, 78, 199, 254, 255, 263, 270]
      
      stat = if move.damage_class_id == 2 then @attack else @spattack
      stab = if move.type in @types then 1.5 else 1
      
      #TODO Add a multiplier for useful types (effective against pokemon's weak types)
      move.score = move.power * stab * stat * move.accuracy
      moves.push(move)
    
    moves.sort (a,b) -> b.score - a.score
    
    result = []
    typesCovered = []
    for move in moves
      if move.type not in typesCovered
        result.push(move)
        typesCovered.push(move.type)
        break if typesCovered.length == 4
    
    return result
        

class Battle
  constructor: (@pkmn1, @pkmn2) ->
  
  start: ->
    log = ""
    winner = null
    until winner?
      move1 = this.chooseMove @pkmn1, @pkmn2
      move2 = this.chooseMove @pkmn2, @pkmn1
      throw new Error("Neither pokemon has an attack move.") unless move1? and move2?
      
      #TODO Move priorities
      if @pkmn1.speed > @pkmn2.speed or (@pkmn1.speed == @pkmn2.speed and Math.random() > 0.5)
        attackerPokemon = @pkmn1
        attackerMove = move1
        defenderPokemon = @pkmn2
        defenderMove = move2
      else
        attackerPokemon = @pkmn2
        attackerMove = move2
        defenderPokemon = @pkmn1
        defenderMove = move1
      
      semiturns = 0
      until semiturns == 2 or winner?
        messages = [upperFirst attackerPokemon.trainerAndName() + " used " + titleCase(attackerMove.name) + "!"]
        if Math.random() * 100 > attackerMove.accuracy
          messages.push(upperFirst attackerPokemon.trainerAndName() + "'s attack missed!")

        else
          critical = Math.random() < 0.0625
          random = Math.random() * (1 - 0.85) + 0.85
          damage = this.calculateDamage attackerMove, attackerPokemon, defenderPokemon, critical, random
          
          if damage == 0
            messages.push("It has no effect!")
          else
            effectiveness = defenderPokemon.multipliers[attackerMove.type.toLowerCase()]
            messages.push("It's a critical hit!") if critical
            messages.push("It's super effective!") if effectiveness > 1
            messages.push("It's not very effective...") if effectiveness < 1
            messages.push(upperFirst defenderPokemon.trainerAndName() + " is hit for " + damage + " HP (" + Math.round(damage / defenderPokemon.maxHp * 100) + "%)")
            
            
            defenderPokemon.hp -= damage
            if (defenderPokemon.hp <= 0)
              messages.push(upperFirst defenderPokemon.trainerAndName() + " fained!")
              winner = attackerPokemon
        
        log += messages.join("\n") + "\n\n";
        [attackerPokemon, defenderPokemon] = [defenderPokemon, attackerPokemon]
        [attackerMove, defenderMove] = [defenderMove, attackerMove]
        semiturns++
    
      log += "\n";
      
    log += "The winner is " + winner.trainerAndName() + " with " + winner.hp + " HP (" + Math.round(winner.hp / winner.maxHp * 100) + "%) remaining!"
    return log
    
  chooseMove: (attacker, defender) ->
    #TODO Struggle
    bestMove = null
    bestDamage = 0
    for move in attacker.moves
      damage = this.calculateDamage move, attacker, defender
      if damage > bestDamage
        bestMove = move
        bestDamage = damage
        
    return bestMove
  
  calculateDamage: (move, attacker, defender, critical=false, random=0.925) ->
    attack = if move.damage_class_id == 2 then attacker.attack else attacker.spattack
    defense = if move.damage_class_id == 2 then defender.defense else defender.spdefense
    
    stab = if move.type in attacker.types then 1.5 else 1
    type = defender.multipliers[move.type.toLowerCase()]
    crit = if critical then 2 else 1
    
    return Math.round (0.88 * (attack / defense) * move.power + 2 ) * stab * type * crit * random 


upperFirst = (word) ->
  return word.charAt(0).toUpperCase() + word.slice(1)

titleCase = (string) ->
  return (upperFirst word for word in string.split(' ')).join(' ')

levenstein = (s, t) ->
  n = s.length
  m = t.length
  return m if n is 0
  return n if m is 0

  d       = []
  d[i]    = [] for i in [0..n]
  d[i][0] = i  for i in [0..n]
  d[0][j] = j  for j in [0..m]

  for c1, i in s
    for c2, j in t
      cost = if c1 is c2 then 0 else 1
      d[i+1][j+1] = Math.min d[i][j+1]+1, d[i+1][j]+1, d[i][j] + cost

  d[n][m]

