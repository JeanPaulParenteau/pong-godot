## Accent colors for the UI and gameplay. Keeps the look cohesive: the left
## side / player one is cool, the right side / CPU is warm, and menu buttons are
## tinted by role (primary action, difficulty, neutral). Asset-free — just colors.

# Gameplay
const HUMAN := Color(0.36, 0.80, 1.00)  # left paddle + P1 score
const CPU := Color(1.00, 0.50, 0.32)    # right paddle + CPU score
const BALL := Color(1.00, 0.96, 0.80)   # warm white
const LINE := Color(0.50, 0.68, 0.90)   # field border + center dashes

# Menu / button tints
const ACCENT := Color(0.40, 0.72, 1.00)  # primary: Play Online / Rematch
const EASY := Color(0.50, 0.85, 0.55)
const MEDIUM := Color(0.95, 0.78, 0.38)
const HARD := Color(0.95, 0.48, 0.45)
const NEUTRAL := Color(0.82, 0.82, 0.88)

# Menu chrome
const CARD_BG := Color(0.10, 0.11, 0.14, 0.96)
const BUTTON_TEXT := Color(0.08, 0.09, 0.11)  # dark text on tinted buttons
