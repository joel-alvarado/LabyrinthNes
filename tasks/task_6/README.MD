# I was not able to complete it

Sadly, due to crunching and time constraints from my other courses, I was not able to complete this task. I am sorry for the inconvenience.

A big chunk of the code is already written in task_5, so I hope that I can get some bonus points
off of that. What is present:

- Transitions from left to right part of stage when end of current side is reached
- Transitions from stage 1 to stage 2 when far right of stage 1 is reached (slightly buggy, attributes aren't being weitten correctly)
- Logic for knowing exactly which side and stage is being played, and which side and stage to transition to

What is missing:

- Missing timer
  - This can be easily done with 2 bytes for each digit, and a counter that decrements the unit every 60 frames, and if unit is 0 then decrement the tens and reset the unit to 9. For the actual sprite, a simple lookup table can be used to get the correct sprite for each digit
  - Missing game over screen since timer is missing (simple nametable update with "Game Over" written to it, and a simple loop that waits for a button press to reset the game)
  - Missing death animation since timer is missing (Should be simple? Not sure, maybe just a loop that replaces with a corresponding part of a skull, then transitions to game over screen)
  - Missing stage cleared (simple nametable update with "Stage Cleared" written to it, and a simple loop that waits for a button press to move to the next stage)
  - Missing stage 2 cleared and showing sum of times for both stages
    - This can be done by having a 2 byte counter for each stage, and a 2 byte counter for the sum of both stages. The sum of both stages can be calculated by adding the tens and units of each stage together, and if the unit is greater than 9 then increment the tens and reset the unit to 0. The actual sprite can be done with a lookup table
