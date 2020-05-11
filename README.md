# Visual Approach for X-Plane

**WORKS WITH Zibo 737 only**

This LUA script allows to take a brief look at the threshold of the runway that you arriving to by turning pilot head in the direction of the destination .
This is especially useful during performing visual approaches.

## Requirements

[FlyWithLua NG ](https://forums.x-plane.org/index.php?/files/file/38445-flywithlua-ng-next-generation-edition-for-x-plane-11-win-lin-mac/)

## Installation

Place `visual_approach.lua` file into `<X-Plane>\Resources\plugins\FlyWithLua\Scripts` folder

## Usage

After the script is installed you can assign keyboard or joystick key to look at a runway. Action name `FlyWithLua/VisualApproach/LookAtRnw`

From inside the cockpit press and hold assigned key to turn pilot head, release to return back to original view.

The script takes information about arrival runway from FMS. So in order to make it work FMS should have arrival runway set and route activated, what usually is the case for most of the flights, meaning no additional configuration is needed.
