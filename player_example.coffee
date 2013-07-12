ship   = require("./ship")
player = new ship.Player process.argv[2..4]...

# Turn off leds
player.off = ->
	console.log "<#{player.id}> LED: OFF"
	if player.r_led_ready then player.r_led.set(0)
	if player.w_led_ready then player.w_led.set(0)

# Turn on red led
player.red = ->
	console.log "<#{player.id}> LED: RED"
	if player.r_led_ready then player.r_led.set(1)

# Turn on white led
player.white = ->
	console.log "<#{player.id}> LED: WHITE"
	if player.w_led_ready then player.w_led.set(1)

# Enable the button
if player.button
	player.button.on "change", (val) ->
		if val == 1 then player.fire()