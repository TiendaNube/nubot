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
defensedex = JSON.parse fs.readFileSync('pokemonjson/types_defense.json').toString()

module.exports = (robot) ->
  robot.respond /fight (m[ey] )?((@[A-Za-z0-9]+)'s )?([A-Za-z .']+) against ((@[A-Za-z0-9]+)'s )?([A-Za-z .']+)/i, (msg) ->
    pkmn1 = new Pokemon msg.match[4], msg.match[3]
    pkmn2 = new Pokemon msg.match[7], msg.match[6] ? "the foe"
    battle = new Battle(pkmn1, pkmn2)
    msg.send battle.start()
  
  robot.respond /build me ([A-Za-z .]+)/i, (msg) ->
    pkmn = new Pokemon msg.match[1]
    msg.send pkmn.moves.join("\n")
    
  robot.respond /build debug me ([A-Za-z .]+)/i, (msg) ->
    pkmn = new Pokemon msg.match[1]
    moves = []
    for move in pkmn.movesDebug
      moves.push(move + " " + move.score)
      
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
    @helpfulTypes = this.calculateHelpfulTypes()
    @moves = this.chooseMoves pokedex.moves
  
  trainerAndName: ->
    if not @trainer?
      return "your " + @name
    else
      return @trainer + "'s " + @name
    
  statFormula: (base) -> 36 + 2 * base
  
  calculateHelpfulTypes: ->
    weaknesses = (type for type, effectiveness of @multipliers when effectiveness > 1)
    helpfulTypes = []
    for weakness in weaknesses
      helpfulTypes = helpfulTypes.concat (type for type, effectiveness of defensedex[weakness] when effectiveness > 1)
      
    return helpfulTypes
  
  chooseMoves: (pokedex) ->
    allMoves = pokedex.level.concat(pokedex.tmhm).concat(pokedex.egg).concat(pokedex.tutor)
    moves = []
    for movePointer in allMoves
      try
        move = new Move movePointer.name
      catch err
        continue
      
      continue if move.blacklisted()
      
      if move.type in @types
        typeMultiplier = 1.5
      else
        typeMultiplier = if move.type.toLowerCase() in @helpfulTypes then 1.1 else 1
      
      stat = if move.damageClass == Move.DAMAGE_PHYSICAL then @attack else @spattack
      effect = move.scoreModifier()
      
      move.score = move.power * typeMultiplier * stat * move.accuracy * effect
      moves.push(move)
    
    moves.sort (a,b) -> b.score - a.score
    @movesDebug = moves
    
    result = []
    typesCovered = []
    for move in moves
      if move.type not in typesCovered
        result.push(move)
        typesCovered.push(move.type)
        break if typesCovered.length == 4
    
    if result.length == 0
      result = [ new Move('struggle') ]
    
    return result


class Move
  @DAMAGE_NONE = 1
  @DAMAGE_PHYSICAL = 2
  @DAMAGE_SPECIAL = 3
  
  constructor: (name) ->
    move = (item for item in movedex when item.name is name)[0]
    throw new Error("MoveNotFound:" + name) unless move?
    
    @name = titleCase move.name
    @type = move.type
    @power = move.power
    @accuracy = move.accuracy ? 100
    @priority = move.priority
    @effect = move.effect_id
    @damageClass = move.damage_class_id
  
  blacklisted: -> 
    #TODO Last 4 could be implemented more easily.
    blacklist = [8, 9, 27, 28, 39, 40, 76, 81, 136, 146, 149, 152, 156, 159, 160, 191, 205, 230, 247, 249, 256, 257, 273, 293, 298, 312, 332, 333, 30, 45, 46, 78]
    return @damageClass == @constructor.DAMAGE_NONE or @effect in blacklist or @power < 2
  
  scoreModifier: ->
    base = switch @effect
      # Heal
      when 4 then 1.25
      # Recoil
      when 49, 199, 254, 263 then 0.85
      when 270 then 0.5
      else 1
    
    base *= 1.33 if @priority > 0
    return base
  
  chooseModifier: (attacker, defender, damage) ->
    base = @accuracy / 100
    base *= 1 - this.recoil(damage) / attacker.hp / 1.5
    
    if attacker.hp < attacker.maxHp
      base *= 1 + this.heal(damage) / (attacker.maxHp - attacker.hp) / 1.5
    
    if @priority > 0 and damage >= defender.hp
      base *= 5
    
    return base
  
  recoil: (damage) ->
    switch @effect
      when 49 then damage / 4
      when 199, 254, 263 then damage / 3
      when 270 then damage / 2
      else 0
      
  heal: (damage) ->
    if @effect == 4 then damage / 2 else 0
  
  afterDamage: (attacker, defender, damage, messages) ->
    switch @effect
      when 4 then selfHeal = this.heal damage
      when 49, 199, 254, 263, 270 then selfDamage = this.recoil damage
      when 255 then selfDamage = attacker.maxHp / 4
    
    if selfHeal? and attacker.hp < attacker.maxHp
      selfHeal = Math.min(Math.round(selfHeal), attacker.maxHp - attacker.hp)
      attacker.hp += selfHeal
      messages.push(upperFirst attacker.trainerAndName() + " healed " +  selfHeal + " HP (" + Math.round(selfHeal / attacker.maxHp * 100) + "%)!")
    
    if selfDamage?
      selfDamage = Math.round(selfDamage)
      attacker.hp -= selfDamage
      messages.push(upperFirst attacker.trainerAndName() + " is hurt " +  selfDamage + " HP (" + Math.round(selfDamage / attacker.maxHp * 100) + "%) by recoil!")

  toString: ->
    return @name + " (" + @type + " - " + @power + " power)"

class Battle
  constructor: (@pkmn1, @pkmn2) ->
  
  start: ->
    log = ""
    winner = null
    until winner?
      move1 = this.chooseMove @pkmn1, @pkmn2
      move2 = this.chooseMove @pkmn2, @pkmn1
      throw new Error("One of the pokemon doesn't have an attack move.") unless move1? and move2?
      
      if move1.priority == move2.priority
        pkmn1GoesFirst = @pkmn1.speed > @pkmn2.speed or (@pkmn1.speed == @pkmn2.speed and Math.random() > 0.5)
      else
        pkmn1GoesFirst = move1.priority > move2.priority
      
      if (pkmn1GoesFirst)
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
        messages = [upperFirst attackerPokemon.trainerAndName() + " used " + attackerMove.name + "!"]
        if Math.random() * 100 > attackerMove.accuracy
          messages.push(upperFirst attackerPokemon.trainerAndName() + "'s attack missed!")

        else
          critical = Math.random() < 0.0625
          random = Math.random() * (1 - 0.85) + 0.85
          damage = this.calculateDamage attackerMove, attackerPokemon, defenderPokemon, critical, random
          
          if damage == 0
            messages.push("It has no effect!")
          else
            damage = defenderPokemon.hp if damage > defenderPokemon.hp
            
            effectiveness = defenderPokemon.multipliers[attackerMove.type.toLowerCase()]
            messages.push("It's a critical hit!") if critical
            messages.push("It's super effective!") if effectiveness > 1
            messages.push("It's not very effective...") if effectiveness < 1
            messages.push(upperFirst defenderPokemon.trainerAndName() + " is hit for " + damage + " HP (" + Math.round(damage / defenderPokemon.maxHp * 100) + "%)")
            
            defenderPokemon.hp -= damage
            if (defenderPokemon.hp <= 0)
              messages.push(upperFirst defenderPokemon.trainerAndName() + " fained!")
              winner = attackerPokemon
              
            attackerMove.afterDamage attackerPokemon, defenderPokemon, damage, messages
            if (attackerPokemon.hp <= 0)
              messages.push(upperFirst attackerPokemon.trainerAndName() + " fained!")
              winner = defenderPokemon unless winner?
        
        log += messages.join("\n") + "\n\n";
        [attackerPokemon, defenderPokemon] = [defenderPokemon, attackerPokemon]
        [attackerMove, defenderMove] = [defenderMove, attackerMove]
        semiturns++
    
      log += "\n";
    
    winner.hp = 0 if winner.hp < 0  
    log += "The winner is " + winner.trainerAndName() + " with " + winner.hp + " HP (" + Math.round(winner.hp / winner.maxHp * 100) + "%) remaining!"
    return log
    
  chooseMove: (attacker, defender) ->
    bestMove = null
    bestDamage = -1
    for move in attacker.moves
      damage = this.calculateDamage move, attacker, defender
      damage = defender.hp if defender.hp < damage 
      
      damage *= move.chooseModifier attacker, defender, damage
      
      if damage > bestDamage
        bestMove = move
        bestDamage = damage
    
    return bestMove
  
  calculateDamage: (move, attacker, defender, critical = false, random = 0.925) ->
    attack = if move.damageClass == Move.DAMAGE_PHYSICAL then attacker.attack else attacker.spattack
    defense = if move.damageClass == Move.DAMAGE_PHYSICAL then defender.defense else defender.spdefense
    
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

