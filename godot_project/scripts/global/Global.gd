extends Node

# Persists the player's bet choice across the match.
# "Red" | "Blue" | "" (no bet yet)
var player_bet: String = ""

# Running scrap total — persists across rounds.
var total_scrap: int = 100

# Fixed bet per round. GambleScreen deducts this upfront; SewerArena returns
# 2× on a win (net +bet_amount) or 0 on a loss (net −bet_amount already paid).
var bet_amount: int = 50
